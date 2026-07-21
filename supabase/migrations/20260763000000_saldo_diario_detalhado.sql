-- =====================================================================
-- Saldo diario detalhado, historico e materializado
-- =====================================================================
--
-- PROBLEMA
--   saldo_anchor soma o dinheiro pendente no corte atual e
--   fluxo_caixa_diario usa essa ancora para reconstruir toda a curva. Assim,
--   dinheiro ainda nao depositado em 21/07 tambem elevava artificialmente o
--   saldo exibido em 01/07. O Calendario ainda nao permitia abrir a memoria
--   Stone + BB + dinheiro em especie de uma data.
--
-- SOLUCAO
--   - materializar uma linha por dia realizado com saldo Stone, saldo BB,
--     dinheiro pendente naquela data, variacao diaria do dinheiro e total;
--   - usar esse snapshot no saldo realizado e na ancora da projecao do
--     Calendario;
--   - expor uma RPC de uma unica linha para o popover de detalhamento;
--   - incluir a variacao do dinheiro em especie nas entradas/saidas do dia,
--     preservando saldo(d) - saldo(d-1) = entradas - saidas;
--   - atualizar o snapshot no refresh normal de importacao e, nas alteracoes
--     de sangria, por um job pg_cron temporario que se remove ao terminar.
--
-- OBJETOS
--   + public.mv_saldo_caixa_diario_detalhado
--   + private.refresh_saldo_caixa_diario_detalhado()
--   + private.solicitar_refresh_saldo_caixa_diario_detalhado()
--   + private.processar_refresh_saldo_caixa_diario_detalhado()
--   + public.detalhar_saldo_caixa_dia(date)
--   ~ public.refresh_painel()
--   ~ public.salvar_sangria(date, text, numeric)
--   ~ public.alterar_status_sangria(bigint, text)
--   ~ public.listar_calendario_financeiro(date)
--   ~ public.listar_despesas_dia(date)
--
-- RISCO
--   O saldo historico passa a refletir a custodia efetiva de cada data e pode
--   mudar. Depositos/baixas do dinheiro em especie podem elevar os totais
--   brutos de entradas e saidas, mas o efeito liquido permanece correto.
--   O snapshot e pequeno e nao cria cron permanente.
-- =====================================================================

begin;

create materialized view if not exists public.mv_saldo_caixa_diario_detalhado
as
with limites as (
  select
    min(e.data_hora::date) as inicio,
    (select c.dia from public.corte_caixa c limit 1) as fim
  from public.raw_stone_extrato e
  where e.saldo_depois is not null
), dias as (
  select gs::date as dia
  from limites l
  cross join lateral generate_series(
    l.inicio::timestamp,
    l.fim::timestamp,
    interval '1 day'
  ) gs
  where l.inicio is not null
    and l.fim is not null
    and l.fim >= l.inicio
), stone_fechamento as (
  select distinct on (e.data_hora::date)
    e.data_hora::date as dia,
    e.saldo_depois as saldo
  from public.raw_stone_extrato e
  cross join limites l
  where e.saldo_depois is not null
    and e.data_hora::date >= l.inicio
    and e.data_hora::date <= l.fim
  order by e.data_hora::date, e.data_hora desc, e.id desc
), bb_base as (
  select coalesce((
    select si.saldo
    from public.saldo_inicial si
    where lower(si.conta) = 'bb'
    limit 1
  ), 0::numeric) as saldo
), bb_antes as (
  select coalesce(sum(b.valor), 0::numeric) as total
  from public.raw_bb b
  cross join limites l
  where b.data < l.inicio
), bb_movimentos as (
  select b.data as dia, sum(b.valor) as total
  from public.raw_bb b
  cross join limites l
  where b.data >= l.inicio
    and b.data <= l.fim
  group by b.data
), bb_diario as (
  select
    d.dia,
    bb.saldo + ant.total
      + sum(coalesce(m.total, 0::numeric)) over (
          order by d.dia rows between unbounded preceding and current row
        ) as saldo
  from dias d
  cross join bb_base bb
  cross join bb_antes ant
  left join bb_movimentos m on m.dia = d.dia
), especie_eventos as (
  select v.data as dia, v.valor as valor
  from public.venda_especie v
  where v.unidade = 'PRAIA'

  union all

  select
    (v.depositada_em at time zone 'America/Fortaleza')::date as dia,
    -v.valor as valor
  from public.venda_especie v
  where v.unidade = 'PRAIA'
    and v.depositada_em is not null
), especie_antes as (
  select coalesce(sum(e.valor), 0::numeric) as total
  from especie_eventos e
  cross join limites l
  where e.dia < l.inicio
), especie_movimentos as (
  select e.dia, sum(e.valor) as total
  from especie_eventos e
  cross join limites l
  where e.dia >= l.inicio
    and e.dia <= l.fim
  group by e.dia
), especie_diario as (
  select
    d.dia,
    ant.total as saldo_anterior,
    ant.total
      + sum(coalesce(m.total, 0::numeric)) over (
          order by d.dia rows between unbounded preceding and current row
        ) as saldo
  from dias d
  cross join especie_antes ant
  left join especie_movimentos m on m.dia = d.dia
), componentes as (
  select
    d.dia,
    coalesce(sf.saldo, 0::numeric) as saldo_stone,
    coalesce(bb.saldo, 0::numeric) as saldo_bb,
    coalesce(ep.saldo, 0::numeric) as dinheiro_pendente,
    coalesce(ep.saldo_anterior, 0::numeric) as dinheiro_pendente_anterior
  from dias d
  left join lateral (
    select s.saldo
    from stone_fechamento s
    where s.dia <= d.dia
    order by s.dia desc
    limit 1
  ) sf on true
  left join bb_diario bb on bb.dia = d.dia
  left join especie_diario ep on ep.dia = d.dia
), normalizados as (
  select
    c.dia,
    round(c.saldo_stone, 2) as saldo_stone,
    round(c.saldo_bb, 2) as saldo_bb,
    round(c.dinheiro_pendente, 2) as dinheiro_pendente,
    round(c.dinheiro_pendente_anterior, 2) as dinheiro_pendente_anterior
  from componentes c
)
select
  n.dia,
  n.saldo_stone,
  n.saldo_bb,
  n.dinheiro_pendente,
  round(
    n.dinheiro_pendente
      - lag(
          n.dinheiro_pendente,
          1,
          n.dinheiro_pendente_anterior
        ) over (order by n.dia),
    2
  ) as variacao_dinheiro_pendente,
  round(n.saldo_stone + n.saldo_bb + n.dinheiro_pendente, 2) as saldo_total
from normalizados n
order by n.dia
with data;

create unique index if not exists mv_saldo_caixa_diario_detalhado_dia_idx
  on public.mv_saldo_caixa_diario_detalhado (dia);

revoke all privileges on table public.mv_saldo_caixa_diario_detalhado
  from public, anon, authenticated;

comment on materialized view public.mv_saldo_caixa_diario_detalhado is
  'Snapshot diario do caixa realizado: Stone, BB, dinheiro pendente na data, variacao do dinheiro e total.';

create or replace function private.refresh_saldo_caixa_diario_detalhado()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  set local statement_timeout = 0;
  refresh materialized view concurrently public.mv_saldo_caixa_diario_detalhado;
end;
$function$;

revoke all privileges on function private.refresh_saldo_caixa_diario_detalhado()
  from public, anon, authenticated;

create or replace function private.processar_refresh_saldo_caixa_diario_detalhado()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_jobid bigint;
begin
  if not pg_try_advisory_xact_lock(63000000::bigint) then
    return;
  end if;

  begin
    perform private.refresh_saldo_caixa_diario_detalhado();
  exception
    when others then
      raise warning 'Falha ao atualizar saldo diario detalhado: %', sqlerrm;
  end;

  for v_jobid in
    select j.jobid
    from cron.job j
    where j.jobname = 'sirfisher-refresh-saldo-diario-detalhado'
  loop
    perform cron.unschedule(v_jobid);
  end loop;
end;
$function$;

revoke all privileges on function private.processar_refresh_saldo_caixa_diario_detalhado()
  from public, anon, authenticated;

create or replace function private.solicitar_refresh_saldo_caixa_diario_detalhado()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  -- Serializa a solicitacao com o worker. Se uma sangria mudar enquanto o
  -- refresh esta em andamento, esta transacao espera o worker se remover e
  -- agenda uma nova execucao depois do commit, sem perder a alteracao.
  perform pg_advisory_xact_lock(63000000::bigint);

  perform cron.schedule(
    'sirfisher-refresh-saldo-diario-detalhado',
    '5 seconds',
    'select private.processar_refresh_saldo_caixa_diario_detalhado();'
  );
end;
$function$;

revoke all privileges on function private.solicitar_refresh_saldo_caixa_diario_detalhado()
  from public, anon, authenticated;

-- Importacoes continuam usando o refresh completo ja existente.
create or replace function public.refresh_painel()
returns void
language plpgsql
security definer
set search_path = public
as $function$
begin
  set local statement_timeout = 0;
  refresh materialized view concurrently mv_fluxo_caixa_diario;
  refresh materialized view concurrently mv_despesa_mensal;
  refresh materialized view concurrently mv_saldo_caixa_diario_detalhado;
end;
$function$;

-- Alteracoes de sangria apenas agendam o refresh pequeno; nao recalculam o
-- painel pesado dentro da requisicao do navegador.
create or replace function public.salvar_sangria(
  p_data date,
  p_unidade text,
  p_valor numeric
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id bigint;
  v_usuario uuid := auth.uid();
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_data is null or p_valor is null or p_valor < 0 then
    raise exception using errcode = '22023', message = 'Data ou valor invalido.';
  end if;

  insert into public.venda_especie (data, unidade, valor, cadastrado_por)
  values (p_data, coalesce(nullif(p_unidade, ''), 'PRAIA'), p_valor, v_usuario)
  on conflict (data, unidade) do update
    set valor = excluded.valor,
        cadastrado_por = venda_especie.cadastrado_por
  returning id::bigint into v_id;

  perform private.solicitar_refresh_saldo_caixa_diario_detalhado();
  return v_id;
end;
$function$;

create or replace function public.alterar_status_sangria(
  p_id bigint,
  p_acao text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_recolhida_em timestamptz;
  v_depositada_em timestamptz;
  v_usuario uuid := auth.uid();
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  select v.recolhida_em, v.depositada_em
    into v_recolhida_em, v_depositada_em
  from public.venda_especie v
  where v.id = p_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Sangria nao encontrada.';
  end if;

  case p_acao
    when 'recolher' then
      if v_recolhida_em is null then
        update public.venda_especie
           set recolhida_em = now(), recolhida_por = v_usuario
         where id = p_id;
      end if;
    when 'desfazer_recolhimento' then
      if v_depositada_em is not null then
        raise exception using errcode = '22023', message = 'Desfaca o deposito antes do recolhimento.';
      end if;
      update public.venda_especie
         set recolhida_em = null, recolhida_por = null
       where id = p_id;
    when 'depositar' then
      if v_recolhida_em is null then
        raise exception using errcode = '22023', message = 'Marque a sangria como recolhida antes do deposito.';
      end if;
      if v_depositada_em is null then
        update public.venda_especie
           set depositada_em = now(), depositada_por = v_usuario
         where id = p_id;
      end if;
    when 'desfazer_deposito' then
      update public.venda_especie
         set depositada_em = null, depositada_por = null
       where id = p_id;
    else
      raise exception using errcode = '22023', message = 'Acao de sangria invalida.';
  end case;

  perform private.solicitar_refresh_saldo_caixa_diario_detalhado();
end;
$function$;

revoke all privileges on function public.salvar_sangria(date, text, numeric)
  from public, anon;
revoke all privileges on function public.alterar_status_sangria(bigint, text)
  from public, anon;
grant execute on function public.salvar_sangria(date, text, numeric)
  to authenticated;
grant execute on function public.alterar_status_sangria(bigint, text)
  to authenticated;

create or replace function public.detalhar_saldo_caixa_dia(p_dia date)
returns table (
  dia date,
  saldo_stone numeric,
  saldo_bb numeric,
  dinheiro_pendente numeric,
  saldo_total numeric
)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_dia is null then
    raise exception using errcode = '22023', message = 'Dia invalido.';
  end if;

  return query
  select
    s.dia,
    s.saldo_stone,
    s.saldo_bb,
    s.dinheiro_pendente,
    s.saldo_total
  from public.mv_saldo_caixa_diario_detalhado s
  where s.dia = p_dia;
end;
$function$;

comment on function public.detalhar_saldo_caixa_dia(date) is
  'Composicao materializada do saldo realizado do Calendario em uma data.';

revoke all privileges on function public.detalhar_saldo_caixa_dia(date)
  from public, anon, authenticated;
grant execute on function public.detalhar_saldo_caixa_dia(date)
  to authenticated;

create or replace function public.listar_calendario_financeiro(p_mes date)
returns table (
  dia date, dia_semana smallint, modo text, meta_dia numeric,
  meta_acumulada numeric, faturamento_dia numeric,
  faturamento_acumulado numeric, venda_credito numeric, venda_debito numeric,
  venda_pix numeric, venda_extras numeric, venda_dinheiro numeric,
  recebimento_total numeric, recebimento_credito numeric,
  recebimento_debito numeric, recebimento_pix numeric,
  recebimento_projetado numeric, despesa_total numeric,
  despesa_recorrente numeric, despesa_nao_recorrente numeric,
  despesa_recorrente_registrada numeric,
  despesa_recorrente_nao_conciliada numeric, saldo_caixa numeric
)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_mes is null or p_mes <> date_trunc('month', p_mes)::date then
    raise exception using errcode = '22023', message = 'Mes invalido.';
  end if;

  return query
  with dias as (
    select gs::date as dia
    from generate_series(p_mes::timestamp,
      (p_mes + interval '1 month - 1 day')::timestamp, interval '1 day') gs
  ), cortes as (
    select (select cv.dia from public.corte_venda cv) as venda,
           (select cc.dia from public.corte_caixa cc) as caixa
  ), cancelamentos as (
    select r.stone_id, sum(abs(r.valor_bruto)) as valor
    from public.raw_stone_recebiveis r
    where r.categoria ilike '%cancelamento%'
    group by r.stone_id
  ), vendas_stone as (
    select v.data_venda::date as dia,
      sum(case when public.unaccent(lower(v.produto)) like 'credito%'
        then v.valor_bruto - coalesce(c.valor, 0) else 0 end) as credito,
      sum(case when public.unaccent(lower(v.produto)) like 'debito%'
        then v.valor_bruto - coalesce(c.valor, 0) else 0 end) as debito,
      sum(case when lower(v.produto) like 'pix%'
        then v.valor_bruto - coalesce(c.valor, 0) else 0 end) as pix,
      sum(case when public.unaccent(lower(v.produto)) not like 'credito%'
                    and public.unaccent(lower(v.produto)) not like 'debito%'
                    and lower(v.produto) not like 'pix%'
        then v.valor_bruto - coalesce(c.valor, 0) else 0 end) as extras
    from public.raw_stone_vendas v
    left join cancelamentos c on c.stone_id = v.stone_id
    where v.data_venda::date >= p_mes
      and v.data_venda::date < p_mes + interval '1 month'
    group by v.data_venda::date
  ), vendas_dinheiro as (
    select v.data as dia, sum(v.valor) as dinheiro
    from public.venda_especie v
    where v.data >= p_mes and v.data < p_mes + interval '1 month'
    group by v.data
  ), metas as (
    select p.dia, p.meta_dia from public.painel_diario p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ), vendas_total as (
    select p.dia, p.venda, p.tipo from public.projecao_venda_diaria p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ), recebiveis as (
    select r.data_vencimento as dia,
      sum(case when public.unaccent(lower(r.produto)) like 'credito%'
        then r.valor_liquido else 0 end) as credito,
      sum(case when public.unaccent(lower(r.produto)) like 'debito%'
        then r.valor_liquido else 0 end) as debito
    from public.raw_stone_recebiveis r
    where r.data_vencimento >= p_mes
      and r.data_vencimento < p_mes + interval '1 month'
    group by r.data_vencimento
  ), entradas_reais as (
    select
      f.data_caixa as dia,
      sum(case
        when f.origem = 'stone_extrato' and f.tipo = 'Recebível de Cartão'
          then abs(f.valor) else 0 end) as cartoes,
      sum(case
        when f.origem = 'stone_extrato' and f.tipo = 'Transação'
          then abs(f.valor) else 0 end) as qr_code,
      sum(case
        when f.origem is distinct from 'stone_extrato'
          or coalesce(f.tipo, '') <> all(
            array['Recebível de Cartão', 'Transação']::text[]
          ) then abs(f.valor) else 0 end) as outras,
      sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.data_caixa >= p_mes
      and f.data_caixa < p_mes + interval '1 month'
      and f.movimentacao = 'Crédito'
      and f.empresa = any(array['PRAIA', 'BB']::text[])
      and f.origem is distinct from 'bs_cash'
    group by f.data_caixa
  ), recebimentos_projetados as (
    select r.dia, sum(r.valor) as valor from public.recebimento_projetado r
    where r.dia >= p_mes and r.dia < p_mes + interval '1 month' group by r.dia
  ), saidas_reais as (
    select f.data_caixa as dia, sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.data_caixa >= p_mes
      and f.data_caixa < p_mes + interval '1 month'
      and f.movimentacao = 'Débito'
      and f.empresa = any(array['PRAIA', 'BB']::text[])
      and f.origem is distinct from 'bs_cash'
    group by f.data_caixa
  ), recorrentes_reais as (
    select p.data_pagamento as dia, sum(p.valor) as total
    from public.conta_recorrente_pagamento p
    join public.conta_recorrente c on c.id = p.conta_id
    where p.data_pagamento >= p_mes
      and p.data_pagamento < p_mes + interval '1 month'
      and p.situacao = 'pago' and c.tipo = 'despesa' and c.incluir_totais
    group by p.data_pagamento
  ), despesas_fixas_projetadas as (
    select p.dia, sum(p.valor) as total from public.projecao_despesa_fixa p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month' group by p.dia
  ), despesas_diretas_projetadas as (
    select p.dia, sum(p.valor) as total from public.projecao_despesa_direta p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month' group by p.dia
  ), saldos as (
    select p.dia, p.saldo from public.painel_fluxo_caixa p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ), saldos_detalhados as (
    select
      s.dia,
      s.saldo_total,
      s.variacao_dinheiro_pendente
    from public.mv_saldo_caixa_diario_detalhado s
    where s.dia >= p_mes and s.dia < p_mes + interval '1 month'
  ), base as (
    select d.dia, extract(isodow from d.dia)::smallint as dia_semana,
      ct.caixa as corte_caixa,
      case when d.dia <= least(coalesce(ct.venda, d.dia), coalesce(ct.caixa, d.dia)) then 'real'
           when d.dia > greatest(coalesce(ct.venda, d.dia - 1), coalesce(ct.caixa, d.dia - 1)) then 'projetado'
           else 'parcial' end as modo,
      m.meta_dia, vt.venda as faturamento_dia,
      case when vt.tipo = 'real' then vs.credito end as venda_credito,
      case when vt.tipo = 'real' then vs.debito end as venda_debito,
      case when vt.tipo = 'real' then vs.pix end as venda_pix,
      case when vt.tipo = 'real' then vs.extras end as venda_extras,
      case when vt.tipo = 'real' then vd.dinheiro end as venda_dinheiro,
      case when d.dia <= ct.caixa then coalesce(er.cartoes, 0)
           else coalesce(r.credito, 0) end as recebimento_credito,
      case when d.dia <= ct.caixa then null::numeric
           else coalesce(r.debito, 0) end as recebimento_debito,
      case when d.dia <= ct.caixa then coalesce(er.qr_code, 0)
           else 0::numeric end as recebimento_pix,
      case when d.dia <= ct.caixa then
             coalesce(er.outras, 0)
               + greatest(coalesce(sd.variacao_dinheiro_pendente, 0), 0)
           else coalesce(rp.valor, 0) end as recebimento_projetado,
      case when d.dia <= ct.caixa then
             coalesce(er.total, 0)
               + greatest(coalesce(sd.variacao_dinheiro_pendente, 0), 0)
           else coalesce(r.credito, 0) + coalesce(r.debito, 0) + coalesce(rp.valor, 0)
      end as recebimento_total,
      case when d.dia <= ct.caixa then
             coalesce(sr.total, 0)
               + greatest(-coalesce(sd.variacao_dinheiro_pendente, 0), 0)
           else coalesce(dfp.total, 0) + coalesce(ddp.total, 0) end as despesa_total,
      case when d.dia <= ct.caixa then least(coalesce(rr.total, 0), coalesce(sr.total, 0))
           else coalesce(dfp.total, 0) end as despesa_recorrente,
      case when d.dia <= ct.caixa then
             greatest(coalesce(sr.total, 0) - coalesce(rr.total, 0), 0)
               + greatest(-coalesce(sd.variacao_dinheiro_pendente, 0), 0)
           else coalesce(ddp.total, 0) end as despesa_nao_recorrente,
      coalesce(rr.total, 0) as despesa_recorrente_registrada,
      case when d.dia <= ct.caixa then greatest(coalesce(rr.total, 0) - coalesce(sr.total, 0), 0)
           else 0 end as despesa_recorrente_nao_conciliada,
      coalesce(sd.saldo_total, s.saldo) as saldo_real
    from dias d cross join cortes ct
    left join metas m on m.dia = d.dia
    left join vendas_total vt on vt.dia = d.dia
    left join vendas_stone vs on vs.dia = d.dia
    left join vendas_dinheiro vd on vd.dia = d.dia
    left join recebiveis r on r.dia = d.dia
    left join entradas_reais er on er.dia = d.dia
    left join recebimentos_projetados rp on rp.dia = d.dia
    left join saidas_reais sr on sr.dia = d.dia
    left join recorrentes_reais rr on rr.dia = d.dia
    left join despesas_fixas_projetadas dfp on dfp.dia = d.dia
    left join despesas_diretas_projetadas ddp on ddp.dia = d.dia
    left join saldos s on s.dia = d.dia
    left join saldos_detalhados sd on sd.dia = d.dia
  ), calculado as (
    select b.*, coalesce(
      (select s.saldo_total
       from public.mv_saldo_caixa_diario_detalhado s
       where s.dia <= b.corte_caixa
       order by s.dia desc
       limit 1),
      (select p.saldo
       from public.painel_fluxo_caixa p
       where p.dia <= b.corte_caixa
       order by p.dia desc
       limit 1),
      0::numeric
    ) + sum(case when b.dia > b.corte_caixa
          then b.recebimento_total - b.despesa_total else 0::numeric end)
        over (order by b.dia rows between unbounded preceding and current row) as saldo_projetado
    from base b
  )
  select b.dia, b.dia_semana, b.modo, round(b.meta_dia, 2),
    case when max(b.meta_dia) over () is null then null
      else round(sum(coalesce(b.meta_dia, 0)) over (order by b.dia), 2) end,
    round(b.faturamento_dia, 2),
    case when max(b.faturamento_dia) over () is null then null
      else round(sum(coalesce(b.faturamento_dia, 0)) over (order by b.dia), 2) end,
    round(b.venda_credito, 2), round(b.venda_debito, 2), round(b.venda_pix, 2),
    round(b.venda_extras, 2), round(b.venda_dinheiro, 2), round(b.recebimento_total, 2),
    round(b.recebimento_credito, 2), round(b.recebimento_debito, 2),
    round(b.recebimento_pix, 2), round(b.recebimento_projetado, 2),
    round(b.despesa_total, 2), round(b.despesa_recorrente, 2),
    round(b.despesa_nao_recorrente, 2), round(b.despesa_recorrente_registrada, 2),
    round(b.despesa_recorrente_nao_conciliada, 2),
    round(case when b.dia <= b.corte_caixa then b.saldo_real else b.saldo_projetado end, 2)
  from calculado b order by b.dia;
end;
$function$;

comment on function public.listar_calendario_financeiro(date) is
  'Calendario financeiro: saldo realizado detalhado por data e futuro acumulado pela memoria exibida.';

revoke all privileges on function public.listar_calendario_financeiro(date)
  from public, anon;
grant execute on function public.listar_calendario_financeiro(date)
  to authenticated;

create or replace function public.listar_despesas_dia(p_dia date)
returns table (descricao text, categoria text, valor numeric)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_dia is null then
    raise exception using errcode = '22023', message = 'Dia invalido.';
  end if;

  return query
  with linhas as (
    select
      coalesce(nullif(btrim(f.fornecedor), ''),
        nullif(btrim(f.contraparte_nome), ''), f.categoria, f.tipo,
        'Sem descricao') as descricao,
      coalesce(f.categoria, f.tipo, 'Movimentacao de caixa') as categoria,
      round(abs(f.valor), 2) as valor
    from public.fato_financeiro f
    where f.data_caixa = p_dia
      and f.movimentacao = 'Débito'
      and f.empresa = any(array['PRAIA', 'BB']::text[])
      and f.origem is distinct from 'bs_cash'

    union all

    select
      'Baixa do dinheiro pendente'::text,
      'Dinheiro em especie'::text,
      round(abs(s.variacao_dinheiro_pendente), 2)
    from public.mv_saldo_caixa_diario_detalhado s
    where s.dia = p_dia
      and s.variacao_dinheiro_pendente < 0
  )
  select l.descricao, l.categoria, l.valor
  from linhas l
  order by l.valor desc, l.descricao;
end;
$function$;

comment on function public.listar_despesas_dia(date) is
  'Saidas bancarias e baixa do dinheiro pendente que explicam o saldo realizado do Calendario.';

revoke all privileges on function public.listar_despesas_dia(date)
  from public, anon, authenticated;
grant execute on function public.listar_despesas_dia(date)
  to authenticated;

commit;
