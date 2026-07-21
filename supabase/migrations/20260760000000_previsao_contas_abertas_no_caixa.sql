-- =====================================================================
-- Contas recorrentes em aberto passam a compor a previsao de caixa
-- =====================================================================
--
-- PROBLEMA
--   A projecao_despesa_fixa usava somente um colchao generico: media dos tres
--   meses fechados de fato_financeiro menos o realizado no mes. As contas
--   recorrentes abertas nao eram fonte da previsao. Assim, uma conta ativa,
--   com vencimento e media historica (como Pro labore), aparecia no controle
--   operacional, mas nao como saida futura no Caixa.
--
-- SOLUCAO
--   Para cada mes e conta recorrente ativa que seja despesa, esteja marcada
--   incluir_totais, tenha media positiva dos tres pagamentos anteriores e
--   ainda nao tenha pagamento registrado na competencia:
--     - prever o valor medio no dia de vencimento;
--     - se ja venceu apos o corte, trazer para o proximo dia projetado;
--     - abater esse valor do colchao generico antes de distribui-lo pelos
--       demais dias. O total projetado fica no minimo igual ao compromisso
--       cadastrado, sem duplicar a parcela ja contemplada na media historica.
--
-- "incluir_totais" continua sendo o controle explicito: conta fora dos
-- totais operacionais nao entra por acidente na previsao de caixa.
--
-- OBJETOS
--   ~ public.projecao_despesa_fixa
--   ~ public.painel_colchao_despesa_fixa
--
-- RISCOS
--   Uma conta ativa com media historica e sem pagamento na competencia passa
--   a aumentar a previsao, como esperado. Marcar "sem cobranca" ou registrar
--   o pagamento remove a previsao daquele mes. Nenhuma tabela, pagamento ou
--   classificacao financeira e alterada por esta migration.
-- =====================================================================

begin;

create or replace view public.projecao_despesa_fixa as
with corte as (
  select dia from public.corte_caixa
), media as (
  select coalesce(avg(m.total), 0::numeric) as media_mensal
  from (
    select
      date_trunc('month', f.data_competencia) as mes,
      sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.movimentacao like 'D%'
      and f.dre_grupo = any (array[
        'PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'
      ])
      and f.data_competencia >= date_trunc('month', current_date) - interval '3 months'
      and f.data_competencia < date_trunc('month', current_date)
    group by 1
  ) m
), realizado_mes as (
  select
    date_trunc('month', f.data_competencia) as mes,
    sum(abs(f.valor)) as realizado
  from public.fato_financeiro f
  where f.movimentacao like 'D%'
    and f.dre_grupo = any (array[
      'PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'
    ])
  group by 1
), dias_restantes as (
  select c.mes, count(*) as n
  from public.calendario c
  cross join corte ct
  where c.dia > ct.dia
  group by c.mes
), contas_abertas as (
  select
    dr.mes,
    case
      when v.vencimento > ct.dia then v.vencimento
      else (
        select min(c.dia)
        from public.calendario c
        where c.mes = dr.mes and c.dia > ct.dia
      )
    end as dia,
    m.media_3 as valor
  from dias_restantes dr
  cross join corte ct
  join public.conta_recorrente cr
    on cr.ativa
   and cr.tipo = 'despesa'
   and cr.incluir_totais
  cross join lateral (
    select least(
      (dr.mes + (cr.dia_vencimento - 1) * interval '1 day')::date,
      (dr.mes + interval '1 month - 1 day')::date
    ) as vencimento
  ) v
  left join public.conta_recorrente_pagamento cp
    on cp.conta_id = cr.id
   and cp.competencia = dr.mes
  cross join lateral (
    select round(avg(h.valor), 2) as media_3
    from (
      select p.valor
      from public.conta_recorrente_pagamento p
      where p.conta_id = cr.id
        and p.competencia < dr.mes
        and p.situacao = 'pago'
        and p.valor > 0
      order by p.competencia desc
      limit 3
    ) h
  ) m
  where cp.id is null
    and m.media_3 > 0
), contas_abertas_mes as (
  select mes, sum(valor) as total
  from contas_abertas
  group by mes
), contas_abertas_dia as (
  select dia, sum(valor) as total
  from contas_abertas
  where dia is not null
  group by dia
)
select
  c.dia,
  round(
    greatest(
      (select media_mensal from media)
      - coalesce(rm.realizado, 0)
      - coalesce(cam.total, 0),
      0
    ) / dr.n::numeric
    + coalesce(cad.total, 0),
    2
  ) as valor
from public.calendario c
join dias_restantes dr on dr.mes = c.mes
left join realizado_mes rm on rm.mes = c.mes
left join contas_abertas_mes cam on cam.mes = c.mes
left join contas_abertas_dia cad on cad.dia = c.dia
cross join corte ct
where c.dia > ct.dia;

create or replace view public.painel_colchao_despesa_fixa as
with corte as (
  select dia from public.corte_caixa
), media as (
  select coalesce(avg(m.total), 0::numeric) as media_mensal
  from (
    select
      date_trunc('month', f.data_competencia) as mes,
      sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.movimentacao like 'D%'
      and f.dre_grupo = any (array[
        'PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'
      ])
      and f.data_competencia >= date_trunc('month', current_date) - interval '3 months'
      and f.data_competencia < date_trunc('month', current_date)
    group by 1
  ) m
), realizado_mes as (
  select
    date_trunc('month', f.data_competencia) as mes,
    sum(abs(f.valor)) as realizado
  from public.fato_financeiro f
  where f.movimentacao like 'D%'
    and f.dre_grupo = any (array[
      'PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'
    ])
  group by 1
), dias_restantes as (
  select c.mes, count(*) as n
  from public.calendario c
  cross join corte ct
  where c.dia > ct.dia
  group by c.mes
), contas_abertas as (
  select
    dr.mes,
    m.media_3 as valor
  from dias_restantes dr
  join public.conta_recorrente cr
    on cr.ativa
   and cr.tipo = 'despesa'
   and cr.incluir_totais
  left join public.conta_recorrente_pagamento cp
    on cp.conta_id = cr.id
   and cp.competencia = dr.mes
  cross join lateral (
    select round(avg(h.valor), 2) as media_3
    from (
      select p.valor
      from public.conta_recorrente_pagamento p
      where p.conta_id = cr.id
        and p.competencia < dr.mes
        and p.situacao = 'pago'
        and p.valor > 0
      order by p.competencia desc
      limit 3
    ) h
  ) m
  where cp.id is null
    and m.media_3 > 0
), contas_abertas_mes as (
  select mes, sum(valor) as total
  from contas_abertas
  group by mes
)
select
  dr.mes,
  round((select media_mensal from media), 2) as media_tipica,
  round(coalesce(rm.realizado, 0), 2) as ja_realizado,
  round(
    greatest(
      (select media_mensal from media)
      - coalesce(rm.realizado, 0)
      - coalesce(cam.total, 0),
      0
    ),
    2
  ) as colchao,
  dr.n as dias_restantes,
  round(
    greatest(
      (select media_mensal from media)
      - coalesce(rm.realizado, 0)
      - coalesce(cam.total, 0),
      0
    ) / dr.n::numeric,
    2
  ) as valor_dia,
  round(coalesce(cam.total, 0), 2) as contas_abertas
from dias_restantes dr
left join realizado_mes rm on rm.mes = dr.mes
left join contas_abertas_mes cam on cam.mes = dr.mes
order by dr.mes;

commit;
