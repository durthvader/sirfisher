-- =====================================================================
-- Contem acessos publicos a operacoes e dados administrativos
-- =====================================================================
--
-- PROBLEMA
--   As paginas operacionais usavam a role anon para ler e gravar ajustes,
--   classificacoes e vendas em especie. As policies permitiam operacoes sem
--   autenticacao, e refresh_painel() podia ser executada por anon por herdar
--   o privilegio padrao de PUBLIC.
--
-- SOLUCAO
--   - revogar acesso direto de PUBLIC, anon e authenticated aos tres objetos
--     operacionais ate que a autenticacao por papel seja implementada;
--   - remover as policies publicas permissivas;
--   - bloquear leitura publica das duas views administrativas;
--   - permitir refresh_painel() apenas para service_role, alem do dono da
--     funcao e papeis administrativos do banco.
--
-- IMPACTO ESPERADO
--   analise_individual.html, classificar_excecoes.html e venda_especie.html
--   deixam de funcionar para usuarios anonimos ou autenticados sem policies
--   especificas. Essas paginas tambem foram retiradas do artefato publico do
--   GitHub Pages na mesma fase de contencao.
--
--   Os cinco dashboards publicos nao consultam diretamente as tabelas ou
--   views administrativas afetadas. As views de painel existentes continuam
--   inalteradas nesta migration para evitar indisponibilidade antes da fase
--   de autenticacao e revisao de SECURITY DEFINER.
--
-- RISCOS
--   Qualquer integracao externa que use anon ou authenticated diretamente
--   nesses objetos deixara de funcionar. Processos administrativos que usam
--   conexao privilegiada ao Postgres ou service_role nao sao removidos.
-- =====================================================================

-- 1. Bloqueia acesso direto aos objetos operacionais.
revoke all privileges on table public.ajuste_manual
  from public, anon, authenticated;

revoke all privileges on table public.de_para
  from public, anon, authenticated;

revoke all privileges on table public.venda_especie
  from public, anon, authenticated;

-- 2. Remove policies publicas irrestritas.
drop policy if exists ajuste_ins on public.ajuste_manual;
drop policy if exists ajuste_sel on public.ajuste_manual;
drop policy if exists ajuste_upd on public.ajuste_manual;

drop policy if exists "insercao publica de_para" on public.de_para;
drop policy if exists "leitura publica de_para" on public.de_para;

drop policy if exists esp_ins on public.venda_especie;
drop policy if exists esp_sel on public.venda_especie;
drop policy if exists esp_upd on public.venda_especie;

-- 3. Bloqueia acesso direto as views administrativas com dados de
--    contrapartes e classificacao.
revoke all privileges on table public.analise_individual
  from public, anon, authenticated;

revoke all privileges on table public.excecoes
  from public, anon, authenticated;

-- 4. Restringe o refresh privilegiado ao processo de servico.
revoke execute on function public.refresh_painel()
  from public, anon, authenticated;

grant execute on function public.refresh_painel()
  to service_role;
