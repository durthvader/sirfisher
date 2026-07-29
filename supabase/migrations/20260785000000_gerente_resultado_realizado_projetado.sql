-- =====================================================================
-- Painel do gerente: separa resultado realizado e projetado
-- =====================================================================
--
-- PROBLEMA
--   A cascata do gerente mostra somente a DRE realizada, mas o titulo nao
--   deixava o corte explicito. Ao mesmo tempo, as telas administrativas
--   mostram uma projecao de fechamento calculada no front-end. Isso fazia
--   o -1% realizado do gerente parecer incompatível com o lucro projetado.
--
-- SOLUCAO
--   Acrescentar a app_gerente_dre_cascata_perc:
--     - resultado_operacional_projetado_perc;
--     - resultado_liquido_projetado_perc;
--     - em_projecao.
--
--   A formula e a mesma usada por index.html e dre.html:
--     resultado operacional projetado
--       = operacional realizado
--       + receita futura pela tendencia de faturamento
--       - despesa direta futura
--       - despesa fixa futura
--
--     resultado liquido projetado
--       = operacional projetado
--       + itens abaixo da operacao ja realizados
--
--   A view continua expondo apenas percentuais ao gerente. Nenhum valor
--   absoluto novo, tabela ou lancamento e criado ou alterado.
--
-- SEGURANCA E RISCO
--   Mantem security_barrier=true, security_invoker=false, o gate de papel
--   no WHERE e SELECT somente para authenticated. Risco de leitura baixo:
--   duas agregacoes mensais sobre as views de projecao. A formula fica
--   documentada aqui para permitir conferir sua paridade com o front-end.
-- =====================================================================

begin;

create or replace view public.app_gerente_dre_cascata_perc
with (security_barrier = true, security_invoker = false) as
with despesa_fixa_futura as (
  select
    date_trunc('month', p.dia::timestamp with time zone)::date as mes,
    sum(abs(p.valor)) as total
  from public.projecao_despesa_fixa p
  group by 1
),
despesa_direta_futura as (
  select
    date_trunc('month', p.dia::timestamp with time zone)::date as mes,
    sum(abs(p.valor)) as total
  from public.projecao_despesa_direta p
  group by 1
),
base as (
  select
    s.*,
    r.faturamento,
    r.faturamento_proj,
    coalesce(df.total, 0::numeric) as despesa_fixa_futura,
    coalesce(dd.total, 0::numeric) as despesa_direta_futura,
    (
      r.faturamento is not null
      and r.faturamento > 0
      and r.faturamento_proj is not null
      and r.faturamento_proj > 0
      and r.faturamento_proj > r.faturamento + 0.5
    ) as em_projecao
  from public.painel_dre_cascata s
  left join public.painel_resumo_mensal r on r.ano_mes = s.ano_mes
  left join despesa_fixa_futura df on df.mes = s.mes
  left join despesa_direta_futura dd on dd.mes = s.mes
),
projecao as (
  select
    b.*,
    case
      when b.em_projecao
        then b.receita * b.faturamento_proj / nullif(b.faturamento, 0)
      else b.receita
    end as receita_projetada
  from base b
),
resultado as (
  select
    p.*,
    case
      when p.em_projecao then
        p.resultado_operacional
        + greatest(p.receita_projetada - p.receita, 0)
        - p.despesa_direta_futura
        - p.despesa_fixa_futura
      else p.resultado_operacional
    end as resultado_operacional_projetado
  from projecao p
)
select
  s.mes,
  s.ano_mes,
  round((100.0 * s.cmv / nullif(s.receita, 0))::numeric, 1) as cmv_perc,
  round((100.0 * s.impostos / nullif(s.receita, 0))::numeric, 1) as impostos_perc,
  round((100.0 * s.margem_contribuicao / nullif(s.receita, 0))::numeric, 1) as margem_contribuicao_perc,
  round((100.0 * s.pessoal / nullif(s.receita, 0))::numeric, 1) as pessoal_perc,
  round((100.0 * s.infraestrutura / nullif(s.receita, 0))::numeric, 1) as infraestrutura_perc,
  round((100.0 * s.marketing / nullif(s.receita, 0))::numeric, 1) as marketing_perc,
  round((100.0 * s.resultado_operacional / nullif(s.receita, 0))::numeric, 1) as resultado_operacional_perc,
  round((100.0 * s.nao_operacional / nullif(s.receita, 0))::numeric, 1) as nao_operacional_perc,
  round((100.0 * s.contabil / nullif(s.receita, 0))::numeric, 1) as contabil_perc,
  round((100.0 * s.capex / nullif(s.receita, 0))::numeric, 1) as capex_perc,
  round((100.0 * s.nao_categorizado / nullif(s.receita, 0))::numeric, 1) as nao_categorizado_perc,
  round((100.0 * s.resultado_liquido / nullif(s.receita, 0))::numeric, 1) as resultado_liquido_perc,
  round(
    (100.0 * s.resultado_operacional_projetado
      / nullif(s.receita_projetada, 0)
    )::numeric,
    1
  ) as resultado_operacional_projetado_perc,
  round(
    (100.0 * (
      s.resultado_operacional_projetado
      + s.nao_operacional
      + s.contabil
      + s.capex
      + s.nao_categorizado
    ) / nullif(s.receita_projetada, 0))::numeric,
    1
  ) as resultado_liquido_projetado_perc,
  s.em_projecao
from resultado s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

comment on view public.app_gerente_dre_cascata_perc is
  'Cascata DRE realizada em percentual da receita, com percentuais separados da projecao de fechamento; acesso de admin, socio e gerente.';

revoke all privileges on table public.app_gerente_dre_cascata_perc
from public, anon, authenticated;

grant select on table public.app_gerente_dre_cascata_perc
to authenticated;

commit;
