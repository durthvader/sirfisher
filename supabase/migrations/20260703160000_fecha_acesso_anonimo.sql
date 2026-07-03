-- =====================================================================
-- Fecha o acesso anonimo ao schema publico
-- =====================================================================
--
-- O front publicado consulta dados somente depois do Google OAuth, usando o
-- papel authenticated e os endpoints app_*. Esta migration remove os grants
-- legados de anon/PUBLIC em tabelas, views, materialized views, sequencias e
-- funcoes do schema public. Tambem endurece os privilegios padrao dos objetos
-- criados futuramente pelo papel que executa as migrations.
--
-- Nao altera dados nem privilegios concedidos explicitamente a authenticated
-- ou service_role.
-- =====================================================================

begin;

-- PUBLIC e um pseudo-papel herdado por todos os usuarios. authenticated e
-- service_role recebem USAGE explicitamente antes do fechamento do schema.
revoke all privileges on schema public from public, anon;
grant usage on schema public to authenticated, service_role;

revoke all privileges on all tables in schema public
  from public, anon;

revoke all privileges on all sequences in schema public
  from public, anon;

revoke all privileges on all functions in schema public
  from public, anon;

-- Impede que novos objetos voltem a herdar acesso anonimo por padrao.
alter default privileges in schema public
  revoke all privileges on tables from public, anon;

alter default privileges in schema public
  revoke all privileges on sequences from public, anon;

alter default privileges in schema public
  revoke all privileges on functions from public, anon;

commit;
