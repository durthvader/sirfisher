-- =====================================================================
-- Concede EXECUTE nas funcoes auxiliares de normalizacao ao role de
-- leitura usado pela conexao MCP (supabase_read_only_user)
-- =====================================================================
--
-- PROBLEMA
--   A migration 20260703170000_restringe_authenticated_a_allowlist.sql
--   revogou EXECUTE de todas as funcoes do schema public para papeis
--   nao privilegiados, e a 20260704010000 devolveu apenas para o papel
--   authenticated (front-end) as auxiliares normaliza_nome(text) e
--   so_digitos(text). O role supabase_read_only_user -- usado pela
--   conexao MCP somente-leitura -- ficou de fora.
--
--   As views security_invoker fato_financeiro e excecoes chamam por
--   baixo normaliza_nome e so_digitos. Como a checagem de EXECUTE usa
--   sempre o papel que executa a consulta, qualquer SELECT nessas views
--   (e nas que cascateiam delas: corte_caixa, despesas do calendario,
--   etc.) feito pela conexao de leitura retorna
--   "permission denied for function normaliza_nome".
--
-- SOLUCAO
--   Conceder EXECUTE nas mesmas 2 funcoes auxiliares para
--   supabase_read_only_user, espelhando o grant ja existente para
--   authenticated. Nao altera dados, papeis, policies, nem reabre
--   acesso a anon; o role continua somente-leitura, apenas passa a
--   conseguir ler as views que hoje quebram.
--
--   GRANT e idempotente (re-executavel sem efeito colateral). Guardado
--   em bloco condicional caso o role nao exista no ambiente de preview.
-- =====================================================================

begin;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    grant execute on function public.normaliza_nome(text) to supabase_read_only_user;
    grant execute on function public.so_digitos(text)    to supabase_read_only_user;
  end if;
end
$$;

commit;
