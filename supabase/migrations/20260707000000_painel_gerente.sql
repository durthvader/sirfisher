-- =====================================================================
-- Painel do gerente: views dedicadas com recorte operacional
-- =====================================================================
--
-- O gerente de operacao (salao e cozinha) precisa acompanhar meta e
-- ritmo de vendas do dia a dia. Os indicadores financeiros sensiveis
-- (lucro, margens, CMV, custo de pessoal, saldos bancarios, despesas
-- por fornecedor) permanecem restritos a admin/socio: alem de risco de
-- gestao e seguranca, sao dados que nao devem circular por conta de
-- eventuais disputas trabalhistas.
--
-- Novas views, no mesmo padrao dos wrappers app_* existentes
-- (security_barrier, security_invoker=false, checagem de papel no
-- WHERE, grant somente para authenticated):
--   - app_gerente_resumo_mensal: faturamento, meta, % meta, projecao,
--     ticket medio e nº de vendas. SEM resultado, cmv, pessoal,
--     margens e saldos;
--   - app_gerente_meta_diaria: venda x meta por dia do mes;
--   - app_gerente_gasto_grupo: composicao dos gastos por grupo em
--     percentual do total do mes, sem valores absolutos (nao permite
--     reconstruir valores nem resultado);
--   - app_gerente_movimento_hora: quantidade de transacoes por hora
--     (apoio a escala de salao/cozinha), sem valores;
--   - app_gerente_ultima_carga: carimbo da ultima atualizacao.
--
-- Tambem cadastra gerente.html em pagina_permissao (socio + gerente;
-- admin sempre acessa tudo).
-- =====================================================================

begin;

create or replace view public.app_gerente_resumo_mensal
with (security_barrier = true, security_invoker = false) as
select s.mes, s.ano_mes, s.ano, s.faturamento, s.faturamento_proj,
       s.qtd_vendas, s.ticket_medio, s.meta, s.perc_meta
from public.painel_resumo_mensal s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

create or replace view public.app_gerente_meta_diaria
with (security_barrier = true, security_invoker = false) as
select s.dia, s.mes, s.venda_dia, s.meta_dia
from public.painel_diario s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

create or replace view public.app_gerente_gasto_grupo
with (security_barrier = true, security_invoker = false) as
select s.mes, s.ano_mes, s.grupo,
       round((100.0 * s.valor / nullif(sum(s.valor) over (partition by s.ano_mes), 0))::numeric, 1) as participacao_perc
from public.painel_composicao_despesa s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

create or replace view public.app_gerente_movimento_hora
with (security_barrier = true, security_invoker = false) as
select s.ano_mes, s.hora, s.qtd
from public.painel_recebimento_hora s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

create or replace view public.app_gerente_ultima_carga
with (security_barrier = true, security_invoker = false) as
select s.ultima
from public.painel_ultima_carga s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

revoke all privileges on table
  public.app_gerente_resumo_mensal,
  public.app_gerente_meta_diaria,
  public.app_gerente_gasto_grupo,
  public.app_gerente_movimento_hora,
  public.app_gerente_ultima_carga
from public, anon, authenticated;

grant select on table
  public.app_gerente_resumo_mensal,
  public.app_gerente_meta_diaria,
  public.app_gerente_gasto_grupo,
  public.app_gerente_movimento_hora,
  public.app_gerente_ultima_carga
to authenticated;

insert into public.pagina_permissao (pagina, papeis) values
  ('gerente.html', array['socio', 'gerente'])
on conflict (pagina) do nothing;

commit;
