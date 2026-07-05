-- =====================================================================
-- Corrige papel antigo (gestor/operador) esquecido no schema private
-- =====================================================================
--
-- A migration de rename de papeis (20260706000000) so verificou o
-- schema public. Ficou de fora um schema private com 25 funcoes
-- security definer no padrao "private.ler_X()", que os wrappers
-- public.app_* as vezes chamam em vez de checar o papel diretamente.
--
-- Confirmado (consulta ao banco antes desta migration) que apenas 3
-- dessas 25 sao efetivamente chamadas por alguma view public.app_*
-- hoje - ler_conciliacao_stone, ler_conciliacao_stone_resumo e
-- ler_painel_meta_real_mensal (usadas por conciliacao.html e
-- planejamento.html). Essas 3 estavam ATIVAMENTE QUEBRADAS desde o
-- rename: o papel 'gestor' nao existe mais (virou 'socio'), entao
-- usuario_tem_papel(array['admin','gestor']) nunca era verdadeiro
-- para socio, e as duas paginas voltavam vazias sem erro nenhum -
-- silenciosamente, ha varios dias.
--
-- As outras 22 funcoes sao codigo orfao (nenhuma view public.app_*
-- atual as chama - os paineis financeiros hoje leem direto das
-- tabelas painel_* com o proprio usuario_tem_papel no WHERE, sem
-- passar por aqui). Corrigidas mesmo assim por consistencia e para
-- nao deixar uma armadilha para o futuro.
-- =====================================================================

begin;

create or replace function private.ler_analise_individual()
 returns setof analise_individual
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.analise_individual s
  where public.usuario_tem_papel(array['socio', 'gerente']::text[]);
$function$;

create or replace function private.ler_categoria_dre()
 returns setof categoria_dre
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.categoria_dre s
  where public.usuario_tem_papel(array['socio', 'gerente']::text[]);
$function$;

create or replace function private.ler_conciliacao_stone()
 returns setof conciliacao_stone
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select c.* from public.conciliacao_stone c
  where public.usuario_tem_papel(array['admin', 'socio']::text[]);
$function$;

create or replace function private.ler_conciliacao_stone_resumo()
 returns setof conciliacao_stone_resumo
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select c.* from public.conciliacao_stone_resumo c
  where public.usuario_tem_papel(array['admin', 'socio']::text[]);
$function$;

create or replace function private.ler_excecoes()
 returns setof excecoes
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.excecoes s
  where public.usuario_tem_papel(array['socio', 'gerente']::text[]);
$function$;

create or replace function private.ler_mv_despesa_mensal()
 returns setof mv_despesa_mensal
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.mv_despesa_mensal s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_cargas()
 returns setof painel_cargas
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_cargas s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_composicao_despesa()
 returns setof painel_composicao_despesa
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_composicao_despesa s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_diario()
 returns setof painel_diario
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_diario s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_dre_cascata()
 returns setof painel_dre_cascata
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_dre_cascata s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_fluxo_caixa()
 returns setof painel_fluxo_caixa
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_fluxo_caixa s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_margem_contribuicao()
 returns setof painel_margem_contribuicao
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_margem_contribuicao s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_meta_real_mensal()
 returns setof painel_meta_real_mensal
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select m.* from public.painel_meta_real_mensal m
  where public.usuario_tem_papel(array['admin', 'socio']::text[]);
$function$;

create or replace function private.ler_painel_recebimento_canal()
 returns setof painel_recebimento_canal
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_recebimento_canal s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_recebimento_hora()
 returns setof painel_recebimento_hora
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_recebimento_hora s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_recebimento_resumo()
 returns setof painel_recebimento_resumo
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_recebimento_resumo s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_resumo_mensal()
 returns setof painel_resumo_mensal
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_resumo_mensal s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_saldo_atual()
 returns setof painel_saldo_atual
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_saldo_atual s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_saldo_fim_mes()
 returns setof painel_saldo_fim_mes
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_saldo_fim_mes s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_saldo_por_conta()
 returns setof painel_saldo_por_conta
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_saldo_por_conta s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_painel_ultima_carga()
 returns setof painel_ultima_carga
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.painel_ultima_carga s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_projecao_despesa_direta()
 returns setof projecao_despesa_direta
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.projecao_despesa_direta s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_projecao_despesa_fixa()
 returns setof projecao_despesa_fixa
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.projecao_despesa_fixa s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_recebimento_conhecido()
 returns setof recebimento_conhecido
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.recebimento_conhecido s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

create or replace function private.ler_recebimento_projetado()
 returns setof recebimento_projetado
 language sql stable security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
  select s.* from public.recebimento_projetado s
  where public.usuario_tem_papel(array['socio']::text[]);
$function$;

commit;
