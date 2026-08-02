-- =====================================================================
-- Confirmacao de estorno responde antes do refresh pesado do painel
-- =====================================================================
--
-- O authenticated possui statement_timeout curto. Gravar as duas pontas e
-- executar refresh_painel na mesma RPC fazia toda a transacao ser cancelada.
-- A decisao continua atomica, mas o refresh passa para a fila/pg_cron que ja
-- processa atualizacoes do painel fora da sessao do navegador.
-- =====================================================================

begin;

alter table private.fila_recalculo_saldo
  add column if not exists somente_refresh boolean not null default false;

comment on column private.fila_recalculo_saldo.somente_refresh is
  'Quando true, o worker pula o recalculo de saldo e executa apenas refresh_painel.';

create or replace function private.agendar_refresh_painel(
  p_data_min date,
  p_data_max date
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_id bigint;
begin
  insert into private.fila_recalculo_saldo (
    data_min, data_max, somente_refresh, mensagem
  ) values (
    least(p_data_min, p_data_max),
    greatest(p_data_min, p_data_max),
    true,
    'Atualizacao do painel solicitada pela conciliacao contabil.'
  ) returning id into v_id;

  perform cron.schedule(
    'sirfisher-processar-recalculo-saldo',
    '5 seconds',
    'select private.processar_fila_recalculo_saldo();'
  );

  return v_id;
end;
$function$;

revoke all privileges on function private.agendar_refresh_painel(date, date)
  from public, anon, authenticated;

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
  v_somente_refresh boolean;
  v_mensagem text;
  v_jobid bigint;
begin
  if not pg_try_advisory_xact_lock(58000000::bigint) then
    return;
  end if;

  select f.id, f.data_min, f.data_max, f.somente_refresh
  into v_id, v_data_min, v_data_max, v_somente_refresh
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
      if not v_somente_refresh then
        select r.mensagem into v_mensagem
        from public.recalcular_saldo_fechamento(v_data_min, v_data_max, 0) r
        limit 1;
      end if;

      perform public.refresh_painel();

      update private.fila_recalculo_saldo
      set situacao = 'concluido',
          concluido_em = clock_timestamp(),
          mensagem = case
            when v_somente_refresh then 'Painel atualizado.'
            else coalesce(v_mensagem, 'Saldo recalculado e painel atualizado.')
          end
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

do $migration$
declare
  v_def text;
  v_old constant text := $old$    set local statement_timeout = 0;
    refresh materialized view public.mv_conciliacao_contabil;$old$;
  v_novo_decidir constant text := $new$    perform private.agendar_refresh_painel(
      least(v_a.data_caixa, v_b.data_caixa),
      greatest(v_a.data_caixa, v_b.data_caixa)
    );$new$;
  v_novo_desfazer constant text := $new$    perform private.agendar_refresh_painel(
      least(v_decisao.data_a, v_decisao.data_b),
      greatest(v_decisao.data_a, v_decisao.data_b)
    );$new$;
begin
  v_def := pg_get_functiondef(
    'public.decidir_conciliacao_contabil(text,bigint,text,bigint,text)'::regprocedure
  );
  if position('private.agendar_refresh_painel' in v_def) = 0 then
    if (length(v_def) - length(replace(v_def, v_old, ''))) <> length(v_old) then
      raise exception 'Refresh sincrono nao encontrado exatamente uma vez em decidir_conciliacao_contabil.';
    end if;
    v_def := replace(v_def, v_old, v_novo_decidir);
    execute v_def;
  end if;

  v_def := pg_get_functiondef(
    'public.desfazer_decisao_conciliacao_contabil(bigint)'::regprocedure
  );
  if position('private.agendar_refresh_painel' in v_def) = 0 then
    if (length(v_def) - length(replace(v_def, v_old, ''))) <> length(v_old) then
      raise exception 'Refresh sincrono nao encontrado exatamente uma vez em desfazer_decisao_conciliacao_contabil.';
    end if;
    v_def := replace(v_def, v_old, v_novo_desfazer);
    execute v_def;
  end if;
end;
$migration$;

-- A decisao aparece imediatamente, mesmo antes do refresh em background.
create or replace view public.app_conciliacao_contabil
with (security_barrier = true, security_invoker = false) as
select
  m.origem,
  m.raw_id,
  m.data_caixa,
  m.data_hora,
  m.ano_mes,
  m.valor,
  m.tipo,
  case when d.decisao = 'estorno_confirmado' then 'estornado' else m.categoria end as categoria,
  case when d.decisao = 'estorno_confirmado' then 'CONTABIL' else m.dre_grupo end as dre_grupo,
  m.contraparte_nome,
  m.fornecedor,
  m.espera_zerar,
  case
    when d.decisao = 'estorno_confirmado' then 'estorno_confirmado'
    when d.decisao = 'nao_relacionados' then 'descartado'
    else m.status_conciliacao
  end as status_conciliacao,
  m.qtd_candidatos,
  m.par_origem,
  m.par_raw_id,
  m.par_data,
  m.par_data_hora,
  m.par_valor,
  case when d.decisao = 'estorno_confirmado' then 'estornado' else m.par_categoria end as par_categoria,
  m.par_contraparte,
  m.dias_diferenca,
  m.nivel_reversao,
  m.evidencia_reversao,
  m.minutos_intervalo,
  m.contraparte_confere,
  m.possui_horario,
  d.id as decisao_id,
  d.decisao,
  d.decidido_em,
  m.atualizado_em
from public.mv_conciliacao_contabil m
left join public.conciliacao_contabil_decisao d
  on d.desfeito_em is null
 and d.chave_par = case
   when m.par_origem is null or m.par_raw_id is null then null
   else least(m.origem || ':' || m.raw_id::text,
              m.par_origem || ':' || m.par_raw_id::text)
        || '|'
        || greatest(m.origem || ':' || m.raw_id::text,
                    m.par_origem || ':' || m.par_raw_id::text)
 end
where public.usuario_pode_acessar_pagina('conciliacao_contabil.html');

revoke all on public.app_conciliacao_contabil from public, anon;
grant select on public.app_conciliacao_contabil to authenticated;

commit;
