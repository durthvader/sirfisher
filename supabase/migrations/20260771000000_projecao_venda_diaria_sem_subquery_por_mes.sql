-- =====================================================================
-- projecao_venda_diaria: joins no lugar de subquery correlacionada
-- =====================================================================
--
-- PROBLEMA
--   projecao_venda_diaria custa 1,21s medidos (select sum(venda)), embora
--   todas as suas dependencias juntas custem ~0,35s: venda_diaria 0,11s,
--   calendario 0,055s, peso_mensal 0,056s, tendencia_mes 0,13s.
--
--   A causa e a CTE mes_total, que percorre os 68 meses distintos de
--   calendario e, PARA CADA MES, executa subqueries correlacionadas:
--   soma de venda_diaria do mes, meta_mensal do mes e peso_mensal do mes
--   -- alem de reavaliar tendencia_mes e mes_corte dentro do CASE. Sao
--   centenas de execucoes para produzir 68 linhas.
--
--   O custo se multiplica porque outras duas views derivam desta e a
--   reexpandem: recebimento_projetado (1,20s) e projecao_despesa_direta
--   (1,18s). No calendario as tres apareciam juntas, somando ~3,6s dos
--   ~8s da RPC -- principal causa do timeout intermitente de
--   calendario.html.
--
-- SOLUCAO
--   Reescrever mes_total com agregacao unica + left joins, mantendo a
--   mesma regra de negocio:
--     - mes anterior ao mes do corte  -> realizado do mes (venda_diaria)
--     - mes do corte                  -> tendencia, ou meta se nao houver
--     - meses futuros                 -> meta do mes
--   e o mesmo rateio por peso_ajustado para os dias apos o corte.
--
--   Cuidados na equivalencia:
--     - tendencia_mes pode ter zero linhas; o `(select tendencia from
--       tendencia_mes)` original devolveria null nesse caso, entao o join
--       e LEFT JOIN LATERAL ... ON true (nao cross join, que apagaria as
--       linhas).
--     - meta_mensal so entra com unidade = 'PRAIA', como no original, e
--       nao tem duplicata por (mes, unidade) -- conferido antes.
--     - corte_venda e uma view de uma linha so (select least(...)), entao
--       o cross join com ela e seguro.
--     - venda_diaria agregada por mes de uma vez, em vez de uma subquery
--       por mes.
--
--   Resultado conferido linha a linha contra a versao anterior (todas as
--   2.064 linhas, colunas dia/mes/peso/venda/tipo) antes desta migration.
--
-- OBJETOS
--   ~ public.projecao_venda_diaria (create or replace view; mesmas
--     colunas, mesmos tipos, mesmos valores)
--
-- EFEITO EM CASCATA (sem alteracao direta; leem esta view)
--   recebimento_projetado, projecao_despesa_direta, listar_calendario_
--   financeiro, caixa.html, dre.html e vendas.html -- todos ficam mais
--   rapidos pelo mesmo motivo.
--
-- RISCO: baixo. Sem mudanca de schema, permissao ou regra financeira.
-- =====================================================================

create or replace view public.projecao_venda_diaria as
with corte as (
  select dia from public.corte_venda
), mes_corte as (
  select date_trunc('month', cv.dia::timestamp with time zone)::date as mes
  from public.corte_venda cv
), venda_por_mes as (
  -- Uma agregacao para todos os meses, no lugar de uma subquery por mes.
  select date_trunc('month', v.dia::timestamp with time zone)::date as mes,
         sum(v.bruto) as bruto
  from public.venda_diaria v
  group by 1
), meta_praia as (
  select m.mes, m.meta_bruta
  from public.meta_mensal m
  where m.unidade = 'PRAIA'
), meses as (
  select distinct c.mes from public.calendario c
), mes_total as (
  select
    ms.mes,
    case
      when ms.mes < mc.mes then coalesce(vm.bruto, 0::numeric)
      when ms.mes = mc.mes then coalesce(t.tendencia, mp.meta_bruta)
      else mp.meta_bruta
    end as total_esperado,
    pm.peso_total
  from meses ms
  cross join mes_corte mc
  left join venda_por_mes vm on vm.mes = ms.mes
  left join meta_praia mp on mp.mes = ms.mes
  left join public.peso_mensal pm on pm.mes = ms.mes
  -- tendencia_mes pode nao ter linha; lateral com on true preserva o
  -- comportamento do subselect original (devolve null).
  left join lateral (
    select tm.tendencia from public.tendencia_mes tm
  ) t on true
)
select
  c.dia,
  c.mes,
  c.peso_ajustado as peso,
  case
    when c.dia <= (select ct.dia from corte ct) then coalesce(v.bruto, 0::numeric)
    else round(
      coalesce(mt.total_esperado, 0::numeric) * c.peso_ajustado
        / nullif(mt.peso_total, 0::numeric), 2)
  end as venda,
  case
    when c.dia <= (select ct.dia from corte ct) then 'real'::text
    else 'projetado'::text
  end as tipo
from public.calendario c
left join public.venda_diaria v on v.dia = c.dia
left join mes_total mt on mt.mes = c.mes;

comment on view public.projecao_venda_diaria is
  'Venda diaria realizada ate o corte e projetada depois; mes_total por joins, sem subquery por mes.';
