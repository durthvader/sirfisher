-- =====================================================================
-- Concede EXECUTE nas funcoes auxiliares de normalizacao para authenticated
-- =====================================================================
--
-- A migration 20260703170000_restringe_authenticated_a_allowlist.sql revogou
-- EXECUTE de todas as funcoes do schema public para o papel authenticated e
-- devolveu apenas papel_usuario_atual() e usuario_tem_papel(text[]).
--
-- As views app_* usadas pelos dashboards (ex.: app_painel_resumo_mensal,
-- app_painel_composicao_despesa) chamam por baixo funcoes auxiliares de
-- normalizacao de texto -- normaliza_nome, so_digitos e unaccent. Mesmo essas
-- views sendo security_invoker = false, a checagem de EXECUTE em funcoes usa
-- sempre o papel que esta de fato executando a consulta (authenticated), nao
-- o dono da view. Sem essas concessoes, qualquer usuario autenticado (admin,
-- gestor ou operador) recebe "permission denied for function normaliza_nome"
-- ao abrir index, vendas, caixa, dre ou despesas.
--
-- Esta migration apenas concede EXECUTE nessas 3 funcoes auxiliares para
-- authenticated. Nao altera dados, papeis, policies nem reabre acesso a anon.
-- =====================================================================

begin;

grant execute on function public.normaliza_nome(text) to authenticated;
grant execute on function public.so_digitos(text) to authenticated;
grant execute on function public.unaccent(text) to authenticated;

commit;
