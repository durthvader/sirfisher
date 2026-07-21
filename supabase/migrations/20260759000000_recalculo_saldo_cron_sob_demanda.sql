-- =====================================================================
-- Recalculo de saldo: pg_cron existe somente enquanto houver tarefa
-- =====================================================================
--
-- PROBLEMA
--   A 20260758000000 criou um job a cada 10 segundos. O processamento pesado
--   so acontece com fila pendente, mas o job acorda 8.640 vezes por dia mesmo
--   quando ha apenas 3-5 importacoes por semana. E trabalho e log desnecessario.
--
-- SOLUCAO
--   - Remover o agendamento permanente.
--   - solicitar_recalculo_saldo cria a tarefa e liga um job temporario.
--   - O worker processa a fila e remove o proprio job quando ela esvazia.
--   - Se esta migration encontrar a tarefa de recuperacao da 20260758000000
--     ainda pendente, liga o job uma vez para nao perde-la.
--
-- OBJETOS
--   ~ public.solicitar_recalculo_saldo(date, date)
--   ~ private.processar_fila_recalculo_saldo()
--   - job permanente sirfisher-processar-recalculo-saldo
--
-- RISCO
--   Nenhuma regra financeira muda. O pg_cron continua instalado como executor
--   de background, mas sem job quando a fila esta vazia. Durante processamento
--   ele verifica a cada 5 segundos; normalmente existe por poucos segundos.
-- =====================================================================

begin;

-- Remove qualquer versao permanente deixada pela migration anterior.
do $block$
declare
  v_jobid bigint;
begin
  for v_jobid in
    select j.jobid
    from cron.job j
    where j.jobname = 'sirfisher-processar-recalculo-saldo'
  loop
    perform cron.unschedule(v_jobid);
  end loop;
end;
$block$;

create or replace function public.solicitar_recalculo_saldo(
  p_data_min date,
  p_data_max date default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_data_max date := coalesce(p_data_max, p_data_min);
  v_id bigint;
begin
  if not (
    public.usuario_tem_papel(array['admin']::text[])
    or public.usuario_pode_acessar_pagina('importar.html'::text)
  ) then
    raise exception using errcode = '42501',
      message = 'Sem permissao para recalcular o saldo.';
  end if;

  if p_data_min is null then
    raise exception using errcode = '22023',
      message = 'Informe a data inicial do recalculo.';
  end if;

  if v_data_max < p_data_min then
    raise exception using errcode = '22023',
      message = 'A data final do recalculo nao pode ser anterior a inicial.';
  end if;

  insert into private.fila_recalculo_saldo (data_min, data_max)
  values (p_data_min, v_data_max)
  returning id into v_id;

  -- Nome estavel: chamadas simultaneas atualizam o mesmo job, sem duplicar.
  perform cron.schedule(
    'sirfisher-processar-recalculo-saldo',
    '5 seconds',
    'select private.processar_fila_recalculo_saldo();'
  );

  return jsonb_build_object(
    'id', v_id,
    'situacao', 'pendente',
    'mensagem', 'Recalculo agendado.',
    'em', clock_timestamp()
  );
end;
$function$;

revoke all privileges on function public.solicitar_recalculo_saldo(date, date)
  from public, anon, authenticated;
grant execute on function public.solicitar_recalculo_saldo(date, date)
  to authenticated;

create or replace function private.processar_fila_recalculo_saldo()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_id bigint;
  v_data_min date;
  v_data_max date;
  v_mensagem text;
  v_jobid bigint;
begin
  if not pg_try_advisory_xact_lock(58000000::bigint) then
    return;
  end if;

  select f.id, f.data_min, f.data_max
  into v_id, v_data_min, v_data_max
  from private.fila_recalculo_saldo f
  where f.situacao = 'pendente'
  order by f.id
  for update skip locked
  limit 1;

  if v_id is not null then
    update private.fila_recalculo_saldo
    set situacao = 'processando', iniciado_em = clock_timestamp(), mensagem = null
    where id = v_id;

    begin
      select r.mensagem into v_mensagem
      from public.recalcular_saldo_fechamento(v_data_min, v_data_max, 0) r
      limit 1;

      perform public.refresh_painel();

      update private.fila_recalculo_saldo
      set situacao = 'concluido',
          concluido_em = clock_timestamp(),
          mensagem = coalesce(v_mensagem, 'Saldo recalculado e painel atualizado.')
      where id = v_id;
    exception
      when query_canceled then
        update private.fila_recalculo_saldo
        set situacao = 'erro', concluido_em = clock_timestamp(),
            mensagem = 'Tempo limite excedido no processamento em background.'
        where id = v_id;
      when others then
        update private.fila_recalculo_saldo
        set situacao = 'erro', concluido_em = clock_timestamp(), mensagem = sqlerrm
        where id = v_id;
    end;
  end if;

  delete from private.fila_recalculo_saldo
  where situacao = any (array['concluido', 'erro'])
    and criado_em < clock_timestamp() - interval '30 days';

  -- Sem trabalho restante, o cron deixa de existir. A proxima solicitacao o
  -- cria novamente. Pode haver uma ultima execucao ja enfileirada pelo proprio
  -- pg_cron; ela encontra a fila vazia e encerra sem recalculo.
  if not exists (
    select 1 from private.fila_recalculo_saldo where situacao = 'pendente'
  ) then
    for v_jobid in
      select j.jobid
      from cron.job j
      where j.jobname = 'sirfisher-processar-recalculo-saldo'
    loop
      perform cron.unschedule(v_jobid);
    end loop;
  end if;
end;
$function$;

revoke all privileges on function private.processar_fila_recalculo_saldo()
  from public, anon, authenticated;

-- Preserva a recuperacao automatica criada na migration anterior caso ainda
-- nao tenha sido processada durante a aplicacao das duas migrations.
select cron.schedule(
  'sirfisher-processar-recalculo-saldo',
  '5 seconds',
  'select private.processar_fila_recalculo_saldo();'
)
where exists (
  select 1 from private.fila_recalculo_saldo where situacao = 'pendente'
);

commit;
