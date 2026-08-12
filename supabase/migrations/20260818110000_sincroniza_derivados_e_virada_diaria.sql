-- Sincroniza os derivados que ficaram defasados depois da consolidação da
-- unidade e impede que a virada do corte deixe o saldo diário um dia atrás.
-- Nenhuma tabela raw ou lançamento financeiro é alterado.

begin;

-- O fuso já é administrável. Os cortes não podem continuar presos a uma
-- localidade escrita no SQL; se a configuração ainda não existir, respeitam o
-- fuso da sessão do banco como fallback neutro.
create or replace view public.corte_venda as
with cfg as (
  select coalesce(
    (select c.fuso_horario
       from public.configuracao_operacional c
      where c.singleton
      limit 1),
    current_setting('TimeZone')
  ) as fuso
)
select least(
  (select max(v.data_venda)::date from public.raw_stone_vendas v),
  (select max(e.data) from public.venda_especie e),
  (now() at time zone (select cfg.fuso from cfg))::date - 1
) as dia;

create or replace view public.corte_caixa as
with cfg as (
  select coalesce(
    (select c.fuso_horario
       from public.configuracao_operacional c
      where c.singleton
      limit 1),
    current_setting('TimeZone')
  ) as fuso
)
select least(
  (select max(f.data_caixa) from public.fato_financeiro f),
  (now() at time zone (select cfg.fuso from cfg))::date - 1
) as dia;

-- Compara cada chave e valor das MVs de despesas com a fonte viva. Somente
-- totais globais não bastam: uma classificação pode migrar de grupo mantendo
-- a mesma soma.
create or replace function private.validar_despesas_materializadas()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  if exists (
    with esperado as (
      select
        date_trunc('month', ff.data_competencia::timestamptz)::date as mes,
        to_char(date_trunc('month', ff.data_competencia::timestamptz), 'YYYY-MM') as ano_mes,
        case
          when ff.dre_grupo is null or ff.dre_grupo = '#N/A' then 'Não classificado'
          else ff.dre_grupo
        end as grupo,
        coalesce(nullif(ff.categoria, ''), '(sem categoria)') as categoria,
        coalesce(nullif(ff.fornecedor, ''), nullif(ff.contraparte_nome, ''), '(sem nome)') as fornecedor,
        round(sum(abs(ff.valor)), 2) as valor,
        count(*)::integer as lancamentos
      from public.fato_financeiro ff
      where ff.natureza = 'Despesa'
        and ff.entra_dre
        and ff.unidade = public.unidade_principal_nome()
        and coalesce(ff.dre_grupo, '') <> 'CONTABIL'
        and ff.data_competencia is not null
      group by 1, 2, 3, 4, 5
    ), divergencia as (
      (select * from public.mv_despesa_mensal except all select * from esperado)
      union all
      (select * from esperado except all select * from public.mv_despesa_mensal)
    )
    select 1 from divergencia limit 1
  ) then
    raise exception 'mv_despesa_mensal divergiu de fato_financeiro';
  end if;

  if exists (
    with esperado as (
      select
        ff.data_competencia as dia,
        case
          when ff.dre_grupo is null or ff.dre_grupo = '#N/A' then 'Não classificado'
          else ff.dre_grupo
        end as grupo,
        coalesce(nullif(ff.categoria, ''), '(sem categoria)') as categoria,
        coalesce(nullif(ff.fornecedor, ''), nullif(ff.contraparte_nome, ''), '(sem nome)') as fornecedor,
        round(sum(abs(ff.valor)), 2) as valor,
        count(*)::integer as lancamentos
      from public.fato_financeiro ff
      where ff.natureza = 'Despesa'
        and ff.entra_dre
        and ff.unidade = public.unidade_principal_nome()
        and coalesce(ff.dre_grupo, '') <> 'CONTABIL'
        and ff.data_competencia is not null
      group by 1, 2, 3, 4
    ), divergencia as (
      (select * from public.mv_despesa_diaria except all select * from esperado)
      union all
      (select * from esperado except all select * from public.mv_despesa_diaria)
    )
    select 1 from divergencia limit 1
  ) then
    raise exception 'mv_despesa_diaria divergiu de fato_financeiro';
  end if;
end;
$function$;

create or replace function private.validar_fluxo_materializado()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  if exists (
    with divergencia as (
      (select * from public.mv_fluxo_caixa_diario
       except all
       select dia, mes, tipo, tipo_dia, evento, resultado_real,
              entrada_projetada, saida_projetada, resultado_dia, saldo
         from public.fluxo_caixa_diario)
      union all
      (select dia, mes, tipo, tipo_dia, evento, resultado_real,
              entrada_projetada, saida_projetada, resultado_dia, saldo
         from public.fluxo_caixa_diario
       except all
       select * from public.mv_fluxo_caixa_diario)
    )
    select 1 from divergencia limit 1
  ) then
    raise exception 'mv_fluxo_caixa_diario divergiu de fluxo_caixa_diario';
  end if;
end;
$function$;

create or replace function private.validar_saldo_diario_materializado()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_corte date;
  v_maximo date;
begin
  select c.dia into v_corte from public.corte_caixa c limit 1;
  select max(s.dia) into v_maximo
    from public.mv_saldo_caixa_diario_detalhado s;

  if exists (
    select 1
      from public.raw_stone_extrato e
     where e.saldo_depois is not null
  ) and v_maximo is distinct from v_corte then
    raise exception 'mv_saldo_caixa_diario_detalhado termina em %, corte_caixa é %',
      v_maximo, v_corte;
  end if;

  if exists (
    select 1
      from public.mv_saldo_caixa_diario_detalhado s
     where s.saldo_total is distinct from round(
       s.saldo_stone + s.saldo_bb + s.saldo_inter + s.dinheiro_pendente,
       2
     )
  ) then
    raise exception 'mv_saldo_caixa_diario_detalhado não fecha por componentes';
  end if;

  if v_corte is not null and exists (
    select 1
      from public.mv_saldo_caixa_diario_detalhado s
      cross join public.saldo_anchor a
     where s.dia = v_corte
       and (
         s.saldo_stone is distinct from a.saldo_stone
         or s.saldo_bb is distinct from a.saldo_bb
         or s.dinheiro_pendente is distinct from a.dinheiro_pendente
         or s.saldo_total is distinct from round(a.saldo_total + s.saldo_inter, 2)
       )
  ) then
    raise exception 'snapshot do corte divergiu de saldo_anchor';
  end if;
end;
$function$;

revoke all privileges on function private.validar_despesas_materializadas()
  from public, anon, authenticated;
revoke all privileges on function private.validar_fluxo_materializado()
  from public, anon, authenticated;
revoke all privileges on function private.validar_saldo_diario_materializado()
  from public, anon, authenticated;

-- O refresh completo passa a ser atômico também do ponto de vista lógico: se
-- um derivado não reproduzir sua fonte, toda a atualização é revertida.
create or replace function public.refresh_painel()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  set local statement_timeout = 0;
  refresh materialized view concurrently public.mv_fluxo_caixa_diario;
  refresh materialized view concurrently public.mv_despesa_mensal;
  refresh materialized view concurrently public.mv_despesa_diaria;
  refresh materialized view concurrently public.mv_saldo_caixa_diario_detalhado;
  refresh materialized view concurrently public.mv_conciliacao_contabil;

  perform private.validar_fluxo_materializado();
  perform private.validar_despesas_materializadas();
  perform private.validar_saldo_diario_materializado();
end;
$function$;

-- Uma consulta leve por hora detecta a mudança real do corte. O trabalho
-- pesado só roda uma vez, quando o snapshot está atrasado, respeitando o fuso
-- configurado e sem manter polling de fila de importação.
create or replace function private.processar_virada_financeira()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_corte date;
  v_snapshot date;
begin
  if not pg_try_advisory_xact_lock(18110000::bigint) then
    return;
  end if;

  select c.dia into v_corte from public.corte_caixa c limit 1;
  select max(s.dia) into v_snapshot
    from public.mv_saldo_caixa_diario_detalhado s;

  if v_corte is null or v_snapshot is not distinct from v_corte then
    return;
  end if;

  set local statement_timeout = 0;
  refresh materialized view concurrently public.mv_fluxo_caixa_diario;
  refresh materialized view concurrently public.mv_saldo_caixa_diario_detalhado;
  perform private.validar_fluxo_materializado();
  perform private.validar_saldo_diario_materializado();
end;
$function$;

revoke all privileges on function private.processar_virada_financeira()
  from public, anon, authenticated;

do $cron$
declare
  v_jobid bigint;
begin
  for v_jobid in
    select j.jobid
      from cron.job j
     where j.jobname = 'sirfisher-virada-financeira'
  loop
    perform cron.unschedule(v_jobid);
  end loop;

  perform cron.schedule(
    'sirfisher-virada-financeira',
    '10 * * * *',
    'select private.processar_virada_financeira();'
  );
end;
$cron$;

-- Corrige imediatamente a defasagem existente. O validador aborta a migration
-- antes do commit se qualquer agrupamento ou saldo não fechar.
select public.refresh_painel();

-- A correção anterior do Calendário foi dinâmica. Confere o objeto efetivo no
-- banco (não apenas o texto das migrations) para impedir que esta publicação
-- prossiga se o filtro parametrizado ou o encadeamento entre meses sumiram.
do $validar_calendario$
declare
  v_calendario text := lower(pg_get_functiondef(
    'public.listar_calendario_financeiro(date)'::regprocedure
  ));
  v_despesas text := lower(pg_get_functiondef(
    'public.listar_despesas_dia(date)'::regprocedure
  ));
begin
  if position('least(p_mes, coalesce(ct.caixa, p_mes) + 1)' in v_calendario) = 0
     or position('cfg_fonte.entra_caixa' in v_calendario) = 0
     or position('cfg_historica.entra_caixa_historico' in v_calendario) = 0
     or position('cfg_fonte.entra_caixa' in v_despesas) = 0
     or position('cfg_historica.entra_caixa_historico' in v_despesas) = 0
     or position('f.empresa = any(array[' in v_calendario) > 0
     or position('f.empresa = any(array[' in v_despesas) > 0 then
    raise exception 'Contrato efetivo do Calendário está incompleto; migration cancelada';
  end if;
end;
$validar_calendario$;

comment on function private.validar_despesas_materializadas() is
  'Contrato financeiro: exige igualdade por chave entre as MVs de despesas e fato_financeiro.';
comment on function private.validar_fluxo_materializado() is
  'Contrato financeiro: exige igualdade integral entre a MV e a view viva do fluxo de caixa.';
comment on function private.validar_saldo_diario_materializado() is
  'Contrato financeiro: valida cobertura do corte e fechamento dos componentes do saldo diário.';
comment on function private.processar_virada_financeira() is
  'Atualiza fluxo e saldo somente quando a virada do corte torna o snapshot diário defasado.';

commit;
