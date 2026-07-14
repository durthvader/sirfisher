-- =====================================================================
-- Remove as 22 funcoes private.ler_* orfas desde 20260704000000
-- =====================================================================
--
-- Historico: 20260703120000 converteu 22 views app_* para o padrao
-- security_invoker=true + funcao private.ler_*. No dia seguinte,
-- 20260704000000 (papel admin) recriou as mesmas views lendo direto da
-- base com security_invoker=false — regressao acidental (o commit nao
-- menciona reversao e a propria migration usou o padrao novo nos
-- endpoints que criou). Desde entao as 22 funcoes ficaram orfas:
-- nenhuma view ou funcao as referencia (verificado em producao via
-- pg_depend e pg_proc.prosrc em 2026-07-14), o schema private nao e
-- exposto pela Data API, e elas ja causaram um bug real — apos o rename
-- de papeis ficaram checando papeis inexistentes e as 3 ainda usadas
-- devolviam vazio em silencio (corrigido em a88cd18).
--
-- Esta migration remove apenas as orfas. Continuam em uso (nao tocar):
--   private.ler_conciliacao_stone()          (app_conciliacao_stone)
--   private.ler_conciliacao_stone_resumo()   (app_conciliacao_stone_resumo)
--   private.ler_painel_meta_real_mensal()    (app_painel_meta_real_mensal)
--   private.ler_status_cargas()              (app_status_cargas)
--   private.ler_usuarios_acesso()            (app_usuarios_acesso)
--   private.nome_exibicao_usuario(uuid)      (views de venda especie e
--                                             contas recorrentes)
--
-- Tambem reduz o achado authenticated_security_definer_function_
-- executable do Security Advisor de 36 para ~14 ocorrencias.
-- =====================================================================

begin;

drop function if exists private.ler_analise_individual();
drop function if exists private.ler_categoria_dre();
drop function if exists private.ler_excecoes();
drop function if exists private.ler_mv_despesa_mensal();
drop function if exists private.ler_painel_cargas();
drop function if exists private.ler_painel_composicao_despesa();
drop function if exists private.ler_painel_diario();
drop function if exists private.ler_painel_dre_cascata();
drop function if exists private.ler_painel_fluxo_caixa();
drop function if exists private.ler_painel_margem_contribuicao();
drop function if exists private.ler_painel_recebimento_canal();
drop function if exists private.ler_painel_recebimento_hora();
drop function if exists private.ler_painel_recebimento_resumo();
drop function if exists private.ler_painel_resumo_mensal();
drop function if exists private.ler_painel_saldo_atual();
drop function if exists private.ler_painel_saldo_fim_mes();
drop function if exists private.ler_painel_saldo_por_conta();
drop function if exists private.ler_painel_ultima_carga();
drop function if exists private.ler_projecao_despesa_direta();
drop function if exists private.ler_projecao_despesa_fixa();
drop function if exists private.ler_recebimento_conhecido();
drop function if exists private.ler_recebimento_projetado();

commit;
