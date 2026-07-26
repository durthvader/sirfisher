-- =====================================================================
-- Saldo do BB contava o movimento de 2025 duas vezes
-- =====================================================================
--
-- PROBLEMA
--   saldo_inicial guarda, para a conta 'bb', o valor 12.935,52 com
--   data_base 2025-12-29 e a observacao "Saldo Anterior do extrato BB".
--   Esse numero e um FECHAMENTO: confere exatamente com o extrato de
--   dezembro/2025, que abre em 8.665,78 (saldo anterior de 28/11), tem
--   4.269,74 de movimento no mes e encerra com "S A L D O 12.935,52".
--   Ou seja, ele ja embute todo o movimento de 2025.
--
--   Enquanto raw_bb comecava em 05/01/2026 nao havia movimento anterior a
--   data_base, entao somar "saldo_inicial + todo o raw_bb" acertava por
--   coincidencia. A importacao dos extratos de jul-dez/2025
--   (20260765000000) trouxe 183 lancamentos ANTERIORES a data_base e a
--   conta passou a somar duas vezes o mesmo dinheiro.
--
--   Efeito: "Onde esta o dinheiro" em caixa.html mostrava o BB com
--   59.985,69 em vez de 46.713,02 -- R$ 13.272,67 a mais, exatamente o
--   movimento de 2025. O saldo da Stone estava correto porque vem do
--   proprio saldo_depois do extrato, sem ancora.
--
-- SOLUCAO
--   Os dois lugares que reconstroem o saldo do BB a partir da ancora
--   passam a somar apenas movimento POSTERIOR a data_base:
--     ~ public.saldo_anchor (alimenta painel_saldo_por_conta,
--       painel_saldo_atual e, por elas, fluxo_caixa_diario e o saldo
--       mensal)
--     ~ public.mv_saldo_caixa_diario_detalhado (bb_antes e bb_movimentos)
--
--   O filtro usa coalesce(data_base, '0001-01-01'), entao conta sem
--   saldo_inicial cadastrado continua somando tudo, como antes.
--
--   Conferido: 12.935,52 + 33.777,50 (movimento apos a data_base) =
--   46.713,02.
--
-- OBJETOS
--   ~ public.saldo_anchor (create or replace view)
--   ~ public.mv_saldo_caixa_diario_detalhado (drop cascade + recreate)
--   ~ painel_fluxo_caixa, app_painel_fluxo_caixa, app_painel_saldo_atual,
--     app_painel_saldo_fim_mes, app_gerente_saldo_variacao (recriadas
--     identicas apos o cascade)
--   ~ public.detalhar_saldo_caixa_dia(date) (recriada; le a MV)
--
-- ATENCAO AO CASCADE
--   Os dependentes foram levantados RECURSIVAMENTE (pg_depend em varios
--   niveis), nao so o primeiro. Sao 5: quatro leem a MV direto e
--   app_painel_fluxo_caixa le painel_fluxo_caixa. Foi esse segundo nivel
--   que a 20260765000000 perdeu, quebrando a curva de caixa.html ate a
--   20260772000000. Os cinco sao recriados aqui.
--
-- RISCO: medio. O saldo do BB exibido cai R$ 13.272,67 -- corrige uma
--   superestimativa, nao perde dinheiro. Afeta caixa.html, calendario,
--   painel do gerente e a curva de fluxo. Nenhum lancamento e alterado.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. saldo_anchor: ancora do BB respeita a data_base
-- ---------------------------------------------------------------------
create or replace view public.saldo_anchor as
with corte as (
  select c.dia from public.corte_caixa c limit 1
), bb_data_base as (
  select coalesce((
    select si.data_base
    from public.saldo_inicial si
    where lower(si.conta) = 'bb'
    limit 1
  ), date '0001-01-01') as dia
), calc as (
  select
    (select c.dia from corte c) as data_ref,
    coalesce((
      select e.saldo_depois
      from public.raw_stone_extrato e
      where e.saldo_depois is not null
        and e.data_hora::date <= (select c.dia from corte c)
      order by e.data_hora desc nulls last
      limit 1
    ), 0::numeric) as saldo_stone,
    coalesce((
      select si.saldo
      from public.saldo_inicial si
      where lower(si.conta) = 'bb'
      limit 1
    ), 0::numeric)
    + coalesce((
      select sum(b.valor)
      from public.raw_bb b
      cross join bb_data_base bdb
      where b.data <= (select c.dia from corte c)
        and b.data > bdb.dia
    ), 0::numeric) as saldo_bb,
    coalesce((
      select sum(v.valor)
      from public.venda_especie v
      where v.depositada_em is null
        and v.unidade = 'PRAIA'
        and v.data <= (select c.dia from corte c)
    ), 0::numeric) as dinheiro_pendente
)
select
  data_ref,
  round(saldo_stone, 2) as saldo_stone,
  round(saldo_bb, 2) as saldo_bb,
  round(saldo_stone + saldo_bb + dinheiro_pendente, 2) as saldo_total,
  round(dinheiro_pendente, 2) as dinheiro_pendente
from calc;

comment on view public.saldo_anchor is
  'Ancora de saldo por conta; o BB soma apenas movimento posterior a data_base do saldo_inicial.';

-- ---------------------------------------------------------------------
-- 2. Snapshot diario com o mesmo ajuste
-- ---------------------------------------------------------------------
drop materialized view if exists public.mv_saldo_caixa_diario_detalhado cascade;

create materialized view public.mv_saldo_caixa_diario_detalhado
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
), bb_data_base as (
  -- O saldo_inicial do BB e um FECHAMENTO: ja embute tudo que veio antes
  -- da sua data_base. Somar movimento anterior a ela conta duas vezes.
  select coalesce((
    select si.data_base
    from public.saldo_inicial si
    where lower(si.conta) = 'bb'
    limit 1
  ), date '0001-01-01') as dia
), bb_antes as (
  select coalesce(sum(b.valor), 0::numeric) as total
  from public.raw_bb b
  cross join limites l
  cross join bb_data_base bdb
  where b.data < l.inicio
    and b.data > bdb.dia
), bb_movimentos as (
  select b.data as dia, sum(b.valor) as total
  from public.raw_bb b
  cross join limites l
  cross join bb_data_base bdb
  where b.data >= l.inicio
    and b.data <= l.fim
    and b.data > bdb.dia
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
), inter_antes as (
  -- A conta Inter nasceu em mai/2025 com saldo zero; o extrato importado
  -- cobre a vida inteira da conta, entao a soma acumulada e o saldo.
  select coalesce(sum(i.valor), 0::numeric) as total
  from public.raw_inter i
  cross join limites l
  where i.data < l.inicio
), inter_movimentos as (
  select i.data as dia, sum(i.valor) as total
  from public.raw_inter i
  cross join limites l
  where i.data >= l.inicio
    and i.data <= l.fim
  group by i.data
), inter_diario as (
  select
    d.dia,
    ant.total
      + sum(coalesce(m.total, 0::numeric)) over (
          order by d.dia rows between unbounded preceding and current row
        ) as saldo
  from dias d
  cross join inter_antes ant
  left join inter_movimentos m on m.dia = d.dia
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
    coalesce(it.saldo, 0::numeric) as saldo_inter,
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
  left join inter_diario it on it.dia = d.dia
  left join especie_diario ep on ep.dia = d.dia
), normalizados as (
  select
    c.dia,
    round(c.saldo_stone, 2) as saldo_stone,
    round(c.saldo_bb, 2) as saldo_bb,
    round(c.saldo_inter, 2) as saldo_inter,
    round(c.dinheiro_pendente, 2) as dinheiro_pendente,
    round(c.dinheiro_pendente_anterior, 2) as dinheiro_pendente_anterior
  from componentes c
)
select
  n.dia,
  n.saldo_stone,
  n.saldo_bb,
  n.saldo_inter,
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
  round(n.saldo_stone + n.saldo_bb + n.saldo_inter + n.dinheiro_pendente, 2) as saldo_total
from normalizados n
order by n.dia
with data;

create unique index if not exists mv_saldo_caixa_diario_detalhado_dia_idx
  on public.mv_saldo_caixa_diario_detalhado (dia);

revoke all privileges on table public.mv_saldo_caixa_diario_detalhado
  from public, anon, authenticated;

comment on materialized view public.mv_saldo_caixa_diario_detalhado is
  'Snapshot diario do caixa realizado: Stone, BB, Inter, dinheiro pendente na data, variacao do dinheiro e total.';

-- ---------------------------------------------------------------------
-- 3. Dependentes recriados (5 no total, levantados recursivamente)
-- ---------------------------------------------------------------------
create or replace view public.painel_fluxo_caixa as
select f.dia,
  f.tipo,
  case when f.tipo = 'real' then coalesce(d.saldo_total, f.saldo) else f.saldo end as saldo,
  case when f.tipo = 'real' then coalesce(d.saldo_total, f.saldo) else null::numeric end as saldo_real,
  case when f.tipo = 'projetado' then f.saldo else null::numeric end as saldo_projetado,
  f.entrada_projetada,
  f.saida_projetada,
  case
    when f.tipo = 'real' and d.dia is not null and f.resultado_dia is not null
      then round(f.resultado_dia + coalesce(d.variacao_dinheiro_pendente, 0::numeric), 2)
    else f.resultado_dia
  end as resultado_dia
from mv_fluxo_caixa_diario f
left join mv_saldo_caixa_diario_detalhado d on d.dia = f.dia
order by f.dia;

revoke all privileges on table public.painel_fluxo_caixa
  from public, anon, authenticated;

create or replace view public.app_painel_saldo_atual
with (security_barrier = true, security_invoker = false) as
select s.data_ref,
  s.saldo_atual,
  s.data_comp,
  coalesce(comp.saldo_total, s.saldo_comp) as saldo_comp
from painel_saldo_atual s
left join lateral (
  select d.saldo_total
  from mv_saldo_caixa_diario_detalhado d
  where d.dia <= s.data_comp
  order by d.dia desc
  limit 1
) comp on true
where usuario_tem_papel(array['admin'::text, 'socio'::text]);

revoke all privileges on table public.app_painel_saldo_atual
  from public, anon, authenticated;
grant select on public.app_painel_saldo_atual to authenticated;

create or replace view public.app_painel_saldo_fim_mes
with (security_barrier = true, security_invoker = false) as
with corte as (
  select max(d.dia) as dia
  from mv_saldo_caixa_diario_detalhado d
), ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes,
    d.saldo_total
  from mv_saldo_caixa_diario_detalhado d
  order by date_trunc('month', d.dia)::date, d.dia desc
)
select s.mes,
  s.ano_mes,
  case
    when s.mes < date_trunc('month', c.dia)::date then coalesce(u.saldo_total, s.saldo_fim)
    else s.saldo_fim
  end as saldo_fim,
  s.situacao
from painel_saldo_fim_mes s
cross join corte c
left join ultimo_snapshot_mes u on u.mes = s.mes
where usuario_tem_papel(array['admin'::text, 'socio'::text]);

revoke all privileges on table public.app_painel_saldo_fim_mes
  from public, anon, authenticated;
grant select on public.app_painel_saldo_fim_mes to authenticated;

create or replace view public.app_gerente_saldo_variacao
with (security_barrier = true, security_invoker = false) as
with corte as (
  select max(d.dia) as dia
  from mv_saldo_caixa_diario_detalhado d
), ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes,
    d.saldo_total
  from mv_saldo_caixa_diario_detalhado d
  order by date_trunc('month', d.dia)::date, d.dia desc
), saldos as (
  select s_1.ano_mes,
    case
      when s_1.mes < date_trunc('month', c.dia)::date then coalesce(u.saldo_total, s_1.saldo_fim)
      else s_1.saldo_fim
    end as saldo_fim
  from painel_saldo_fim_mes s_1
  cross join corte c
  left join ultimo_snapshot_mes u on u.mes = s_1.mes
)
select ano_mes,
  round(100.0 * (saldo_fim - lag(saldo_fim) over (order by ano_mes))
    / nullif(abs(lag(saldo_fim) over (order by ano_mes)), 0::numeric), 1) as variacao_perc
from saldos s
where usuario_tem_papel(array['admin'::text, 'socio'::text, 'gerente'::text]);

revoke all privileges on table public.app_gerente_saldo_variacao
  from public, anon, authenticated;
grant select on public.app_gerente_saldo_variacao to authenticated;

-- Segundo nivel do cascade: le painel_fluxo_caixa, nao a MV.
create or replace view public.app_painel_fluxo_caixa
with (security_barrier = true, security_invoker = false) as
  select dia, tipo, saldo, saldo_real, saldo_projetado, entrada_projetada,
         saida_projetada, resultado_dia
  from public.painel_fluxo_caixa s
  where public.usuario_tem_papel(array['admin', 'socio']);

revoke all privileges on table public.app_painel_fluxo_caixa
  from public, anon, authenticated;
grant select on public.app_painel_fluxo_caixa to authenticated;

-- ---------------------------------------------------------------------
-- 4. detalhar_saldo_caixa_dia (le a MV recriada)
-- ---------------------------------------------------------------------
create or replace function public.detalhar_saldo_caixa_dia(p_dia date)
returns table (
  dia date,
  saldo_stone numeric,
  saldo_bb numeric,
  saldo_inter numeric,
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
    s.saldo_inter,
    s.dinheiro_pendente,
    s.saldo_total
  from public.mv_saldo_caixa_diario_detalhado s
  where s.dia = p_dia;
end;
$function$;

revoke all privileges on function public.detalhar_saldo_caixa_dia(date)
  from public, anon, authenticated;
grant execute on function public.detalhar_saldo_caixa_dia(date)
  to authenticated;

commit;
