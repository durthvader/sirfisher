-- =====================================================================
-- Painel do gerente: caixa (variacao %) e cascata do resultado (%)
-- =====================================================================
--
-- Duas views novas, no mesmo padrao das demais app_gerente_*:
--
--   - app_gerente_saldo_variacao: variacao percentual do saldo de
--     fechamento projetado do mes contra o fechamento do mes anterior.
--     Nunca expoe o saldo em reais, so a variacao em %.
--
--   - app_gerente_dre_cascata_perc: a cascata do resultado (receita ->
--     CMV/impostos -> margem de contribuicao -> pessoal/infra/marketing
--     -> resultado operacional -> nao operacional/contabil/capex/nao
--     categorizado -> resultado liquido), com cada linha convertida em
--     percentual da receita do mes. Decisao explicita do usuario, apos
--     aviso de que a cascata completa combinada com o faturamento (ja
--     visivel na tela) permite reconstruir o resultado em reais.
-- =====================================================================

begin;

create or replace view public.app_gerente_saldo_variacao
with (security_barrier = true, security_invoker = false) as
select
  s.ano_mes,
  round(
    (100.0 * (s.saldo_fim - lag(s.saldo_fim) over (order by s.ano_mes))
      / nullif(abs(lag(s.saldo_fim) over (order by s.ano_mes)), 0)
    )::numeric, 1
  ) as variacao_perc
from public.painel_saldo_fim_mes s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

create or replace view public.app_gerente_dre_cascata_perc
with (security_barrier = true, security_invoker = false) as
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
  round((100.0 * s.resultado_liquido / nullif(s.receita, 0))::numeric, 1) as resultado_liquido_perc
from public.painel_dre_cascata s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

revoke all privileges on table
  public.app_gerente_saldo_variacao,
  public.app_gerente_dre_cascata_perc
from public, anon, authenticated;

grant select on table
  public.app_gerente_saldo_variacao,
  public.app_gerente_dre_cascata_perc
to authenticated;

commit;
