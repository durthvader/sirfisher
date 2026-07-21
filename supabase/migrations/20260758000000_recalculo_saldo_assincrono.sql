-- =====================================================================
-- Recalculo de saldo assincrono apos importacao pela web
-- =====================================================================
--
-- PROBLEMA
--   solicitar_recalculo_saldo roda dentro do statement aberto pelo PostgREST.
--   O role authenticated tem statement_timeout de 8 s e o recalculo, que ja
--   custava 5-6 s, passou a exceder esse limite com o crescimento da base.
--   Separar a gravacao do recalculo (20260752000000) protegeu os inserts, mas
--   nao eliminou o teto: os dados ficam salvos e o saldo permanece velho.
--
-- SOLUCAO
--   Enfileirar o periodo e processa-lo em background pelo pg_cron. A chamada
--   do navegador fica curta; o worker roda em outra sessao, fora do timeout
--   de authenticated, recalcula o saldo e atualiza os snapshots do painel.
--   Uma RPC de consulta permite que importar.html acompanhe a tarefa.
--
-- OBJETOS
--   + extension pg_cron (se ainda nao estiver habilitada)
--   + private.fila_recalculo_saldo
--   ~ public.solicitar_recalculo_saldo(date, date)  (agora enfileira)
--   + public.consultar_recalculo_saldo(bigint)
--   + private.processar_fila_recalculo_saldo()
--   + cron job sirfisher-processar-recalculo-saldo (a cada 10 segundos)
--
-- SEGURANCA / RISCO
--   - Nenhuma regra ou valor financeiro muda.
--   - A fila guarda apenas periodo, estado e mensagem tecnica; RLS fica ligada
--     e nao ha grants diretos. O acesso do navegador e somente pelas RPCs com
--     o mesmo gate de importar.html.
--   - O worker serializa as tarefas com advisory lock. Falha fica registrada
--     e nao perde os dados ja importados.
--   - A migration e transacional: se pg_cron nao puder ser habilitado no
--     ambiente, nenhum dos demais objetos fica aplicado pela metade.
-- =====================================================================

begin;

create extension if not exists pg_cron;

create table if not exists private.fila_recalculo_saldo (
  id bigint generated always as identity primary key,
  chave text unique,
  data_min date not null,
  data_max date not null,
  situacao text not null default 'pendente'
    check (situacao = any (array['pendente', 'processando', 'concluido', 'erro'])),
  criado_em timestamptz not null default clock_timestamp(),
  iniciado_em timestamptz,
  concluido_em timestamptz,
  mensagem text,
  check (data_max >= data_min)
);

alter table private.fila_recalculo_saldo enable row level security;
revoke all privileges on table private.fila_recalculo_saldo
  from public, anon, authenticated;

-- Mesmo nome e assinatura usados pela pagina. Agora a resposta e imediata.
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

create or replace function public.consultar_recalculo_saldo(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_resultado jsonb;
begin
  if not (
    public.usuario_tem_papel(array['admin']::text[])
    or public.usuario_pode_acessar_pagina('importar.html'::text)
  ) then
    raise exception using errcode = '42501',
      message = 'Sem permissao para consultar o recalculo do saldo.';
  end if;

  select jsonb_build_object(
    'id', f.id,
    'situacao', f.situacao,
    'mensagem', f.mensagem,
    'criado_em', f.criado_em,
    'iniciado_em', f.iniciado_em,
    'concluido_em', f.concluido_em
  )
  into v_resultado
  from private.fila_recalculo_saldo f
  where f.id = p_id;

  if v_resultado is null then
    raise exception using errcode = 'P0002',
      message = 'Recalculo de saldo nao encontrado.';
  end if;

  return v_resultado;
end;
$function$;

revoke all privileges on function public.consultar_recalculo_saldo(bigint)
  from public, anon, authenticated;
grant execute on function public.consultar_recalculo_saldo(bigint)
  to authenticated;

-- Chamada somente pelo pg_cron. Nao conceder EXECUTE ao navegador.
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
begin
  -- Uma tarefa por vez, inclusive se uma execucao ultrapassar o intervalo do
  -- cron. O proprio pg_cron tambem serializa instancias do mesmo job.
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

  if v_id is null then
    delete from private.fila_recalculo_saldo
    where situacao = any (array['concluido', 'erro'])
      and criado_em < clock_timestamp() - interval '30 days';
    return;
  end if;

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

  delete from private.fila_recalculo_saldo
  where situacao = any (array['concluido', 'erro'])
    and criado_em < clock_timestamp() - interval '30 days';
end;
$function$;

revoke all privileges on function private.processar_fila_recalculo_saldo()
  from public, anon, authenticated;

-- Nome estavel: cron.schedule atualiza o job existente se a migration for
-- reexecutada, em vez de criar duplicatas.
select cron.schedule(
  'sirfisher-processar-recalculo-saldo',
  '10 seconds',
  'select private.processar_fila_recalculo_saldo();'
);

-- Recupera automaticamente o lote que motivou esta migration. O recorte do
-- inicio do ano recompõe também fechamentos anteriores afetados por linhas
-- tardias. A chave deixa o seed idempotente se o arquivo for reexecutado.
insert into private.fila_recalculo_saldo (chave, data_min, data_max, mensagem)
values (
  'migration-20260758000000',
  make_date(extract(year from current_date)::integer, 1, 1),
  current_date,
  'Recalculo inicial apos habilitar o processamento em background.'
)
on conflict (chave) do nothing;

commit;
