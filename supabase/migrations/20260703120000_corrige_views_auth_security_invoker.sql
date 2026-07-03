-- =====================================================================
-- Remove SECURITY DEFINER das views publicas de autorizacao
-- =====================================================================
--
-- As views app_* continuam com os mesmos nomes e colunas, mas passam a ser
-- SECURITY INVOKER. A leitura privilegiada fica encapsulada em funcoes no
-- schema private, fora do schema exposto pela Data API. Cada funcao mantem a
-- verificacao explicita do papel e usa search_path fixo.
--
-- Esta migration nao altera dados nem fecha o acesso anonimo legado.
-- =====================================================================

begin;

create schema if not exists private;
revoke all privileges on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.ler_painel_resumo_mensal()
returns setof public.painel_resumo_mensal
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_resumo_mensal s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_composicao_despesa()
returns setof public.painel_composicao_despesa
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_composicao_despesa s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_saldo_fim_mes()
returns setof public.painel_saldo_fim_mes
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_saldo_fim_mes s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_saldo_atual()
returns setof public.painel_saldo_atual
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_saldo_atual s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_margem_contribuicao()
returns setof public.painel_margem_contribuicao
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_margem_contribuicao s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_ultima_carga()
returns setof public.painel_ultima_carga
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_ultima_carga s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_cargas()
returns setof public.painel_cargas
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_cargas s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_diario()
returns setof public.painel_diario
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_diario s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_recebimento_resumo()
returns setof public.painel_recebimento_resumo
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_recebimento_resumo s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_recebimento_canal()
returns setof public.painel_recebimento_canal
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_recebimento_canal s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_recebimento_hora()
returns setof public.painel_recebimento_hora
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_recebimento_hora s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_fluxo_caixa()
returns setof public.painel_fluxo_caixa
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_fluxo_caixa s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_recebimento_conhecido()
returns setof public.recebimento_conhecido
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.recebimento_conhecido s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_recebimento_projetado()
returns setof public.recebimento_projetado
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.recebimento_projetado s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_projecao_despesa_fixa()
returns setof public.projecao_despesa_fixa
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.projecao_despesa_fixa s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_projecao_despesa_direta()
returns setof public.projecao_despesa_direta
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.projecao_despesa_direta s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_saldo_por_conta()
returns setof public.painel_saldo_por_conta
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_saldo_por_conta s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_dre_cascata()
returns setof public.painel_dre_cascata
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.painel_dre_cascata s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_mv_despesa_mensal()
returns setof public.mv_despesa_mensal
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.mv_despesa_mensal s
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_analise_individual()
returns setof public.analise_individual
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.analise_individual s
  where public.usuario_tem_papel(array['gestor', 'operador']::text[]);
$$;

create or replace function private.ler_excecoes()
returns setof public.excecoes
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.excecoes s
  where public.usuario_tem_papel(array['gestor', 'operador']::text[]);
$$;

create or replace function private.ler_categoria_dre()
returns setof public.categoria_dre
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select s.* from public.categoria_dre s
  where public.usuario_tem_papel(array['gestor', 'operador']::text[]);
$$;

revoke all privileges on function
  private.ler_painel_resumo_mensal(),
  private.ler_painel_composicao_despesa(),
  private.ler_painel_saldo_fim_mes(),
  private.ler_painel_saldo_atual(),
  private.ler_painel_margem_contribuicao(),
  private.ler_painel_ultima_carga(),
  private.ler_painel_cargas(),
  private.ler_painel_diario(),
  private.ler_painel_recebimento_resumo(),
  private.ler_painel_recebimento_canal(),
  private.ler_painel_recebimento_hora(),
  private.ler_painel_fluxo_caixa(),
  private.ler_recebimento_conhecido(),
  private.ler_recebimento_projetado(),
  private.ler_projecao_despesa_fixa(),
  private.ler_projecao_despesa_direta(),
  private.ler_painel_saldo_por_conta(),
  private.ler_painel_dre_cascata(),
  private.ler_mv_despesa_mensal(),
  private.ler_analise_individual(),
  private.ler_excecoes(),
  private.ler_categoria_dre()
from public, anon, authenticated;

grant execute on function
  private.ler_painel_resumo_mensal(),
  private.ler_painel_composicao_despesa(),
  private.ler_painel_saldo_fim_mes(),
  private.ler_painel_saldo_atual(),
  private.ler_painel_margem_contribuicao(),
  private.ler_painel_ultima_carga(),
  private.ler_painel_cargas(),
  private.ler_painel_diario(),
  private.ler_painel_recebimento_resumo(),
  private.ler_painel_recebimento_canal(),
  private.ler_painel_recebimento_hora(),
  private.ler_painel_fluxo_caixa(),
  private.ler_recebimento_conhecido(),
  private.ler_recebimento_projetado(),
  private.ler_projecao_despesa_fixa(),
  private.ler_projecao_despesa_direta(),
  private.ler_painel_saldo_por_conta(),
  private.ler_painel_dre_cascata(),
  private.ler_mv_despesa_mensal(),
  private.ler_analise_individual(),
  private.ler_excecoes(),
  private.ler_categoria_dre()
to authenticated;

create or replace view public.app_painel_resumo_mensal
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_resumo_mensal();

create or replace view public.app_painel_composicao_despesa
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_composicao_despesa();

create or replace view public.app_painel_saldo_fim_mes
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_saldo_fim_mes();

create or replace view public.app_painel_saldo_atual
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_saldo_atual();

create or replace view public.app_painel_margem_contribuicao
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_margem_contribuicao();

create or replace view public.app_painel_ultima_carga
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_ultima_carga();

create or replace view public.app_painel_cargas
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_cargas();

create or replace view public.app_painel_diario
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_diario();

create or replace view public.app_painel_recebimento_resumo
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_recebimento_resumo();

create or replace view public.app_painel_recebimento_canal
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_recebimento_canal();

create or replace view public.app_painel_recebimento_hora
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_recebimento_hora();

create or replace view public.app_painel_fluxo_caixa
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_fluxo_caixa();

create or replace view public.app_recebimento_conhecido
with (security_barrier = true, security_invoker = true) as
select * from private.ler_recebimento_conhecido();

create or replace view public.app_recebimento_projetado
with (security_barrier = true, security_invoker = true) as
select * from private.ler_recebimento_projetado();

create or replace view public.app_projecao_despesa_fixa
with (security_barrier = true, security_invoker = true) as
select * from private.ler_projecao_despesa_fixa();

create or replace view public.app_projecao_despesa_direta
with (security_barrier = true, security_invoker = true) as
select * from private.ler_projecao_despesa_direta();

create or replace view public.app_painel_saldo_por_conta
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_saldo_por_conta();

create or replace view public.app_painel_dre_cascata
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_dre_cascata();

create or replace view public.app_mv_despesa_mensal
with (security_barrier = true, security_invoker = true) as
select * from private.ler_mv_despesa_mensal();

create or replace view public.app_analise_individual
with (security_barrier = true, security_invoker = true) as
select * from private.ler_analise_individual();

create or replace view public.app_excecoes
with (security_barrier = true, security_invoker = true) as
select * from private.ler_excecoes();

create or replace view public.app_categoria_dre
with (security_barrier = true, security_invoker = true) as
select * from private.ler_categoria_dre();

commit;
