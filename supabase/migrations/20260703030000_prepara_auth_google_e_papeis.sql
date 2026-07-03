-- =====================================================================
-- Prepara Google OAuth, papeis e endpoints protegidos do aplicativo
-- =====================================================================
--
-- Esta migration nao habilita o provedor Google: Client ID e Client Secret
-- devem ser configurados exclusivamente nos paineis do Google e Supabase.
-- Ela cria a camada de autorizacao usada pelo front depois do login.
--
-- ROLLOUT EM DUAS ETAPAS
--   A. esta migration cria perfis, policies e wrappers autenticados, mantendo
--      temporariamente leitura anonima nos endpoints antigos dos dashboards;
--   B. depois do primeiro gestor ser provisionado e o login ser validado,
--      uma migration separada revogara a leitura anonima remanescente.
--
-- PAPEIS
--   gestor   -> dashboards e operacoes;
--   operador -> apenas classificacao e venda em especie.
-- =====================================================================

-- 1. Perfil de autorizacao ligado ao usuario do Supabase Auth.
create table if not exists public.perfil_usuario (
  user_id uuid primary key references auth.users(id) on delete cascade,
  papel text not null check (papel in ('gestor', 'operador')),
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

alter table public.perfil_usuario enable row level security;

revoke all privileges on table public.perfil_usuario
  from public, anon, authenticated;
grant select on table public.perfil_usuario to authenticated;

drop policy if exists perfil_usuario_le_proprio on public.perfil_usuario;
create policy perfil_usuario_le_proprio
  on public.perfil_usuario
  for select
  to authenticated
  using (user_id = auth.uid());

-- 2. Funcoes de autorizacao. SECURITY DEFINER e necessario para consultar o
--    perfil sem conceder leitura ampla; auth.uid() continua sendo o usuario
--    do JWT da requisicao.
create or replace function public.papel_usuario_atual()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.papel
  from public.perfil_usuario p
  where p.user_id = auth.uid()
    and p.ativo
  limit 1;
$$;

create or replace function public.usuario_tem_papel(p_papeis text[])
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.perfil_usuario p
    where p.user_id = auth.uid()
      and p.ativo
      and p.papel = any(p_papeis)
  );
$$;

revoke execute on function public.papel_usuario_atual()
  from public, anon;
revoke execute on function public.usuario_tem_papel(text[])
  from public, anon;
grant execute on function public.papel_usuario_atual()
  to authenticated;
grant execute on function public.usuario_tem_papel(text[])
  to authenticated;

-- 3. Escritas operacionais autenticadas.
grant select, insert, update on table public.ajuste_manual to authenticated;
grant insert on table public.de_para to authenticated;
grant select, insert, update on table public.venda_especie to authenticated;

grant usage, select on sequence public.ajuste_manual_id_seq to authenticated;
grant usage, select on sequence public.de_para_id_seq to authenticated;
grant usage, select on sequence public.venda_especie_id_seq to authenticated;

drop policy if exists ajuste_auth_sel on public.ajuste_manual;
drop policy if exists ajuste_auth_ins on public.ajuste_manual;
drop policy if exists ajuste_auth_upd on public.ajuste_manual;

create policy ajuste_auth_sel
  on public.ajuste_manual
  for select
  to authenticated
  using (public.usuario_tem_papel(array['gestor', 'operador']));

create policy ajuste_auth_ins
  on public.ajuste_manual
  for insert
  to authenticated
  with check (public.usuario_tem_papel(array['gestor', 'operador']));

create policy ajuste_auth_upd
  on public.ajuste_manual
  for update
  to authenticated
  using (public.usuario_tem_papel(array['gestor', 'operador']))
  with check (public.usuario_tem_papel(array['gestor', 'operador']));

drop policy if exists de_para_auth_ins on public.de_para;
create policy de_para_auth_ins
  on public.de_para
  for insert
  to authenticated
  with check (public.usuario_tem_papel(array['gestor', 'operador']));

drop policy if exists venda_especie_auth_sel on public.venda_especie;
drop policy if exists venda_especie_auth_ins on public.venda_especie;
drop policy if exists venda_especie_auth_upd on public.venda_especie;

create policy venda_especie_auth_sel
  on public.venda_especie
  for select
  to authenticated
  using (public.usuario_tem_papel(array['gestor', 'operador']));

create policy venda_especie_auth_ins
  on public.venda_especie
  for insert
  to authenticated
  with check (public.usuario_tem_papel(array['gestor', 'operador']));

create policy venda_especie_auth_upd
  on public.venda_especie
  for update
  to authenticated
  using (public.usuario_tem_papel(array['gestor', 'operador']))
  with check (public.usuario_tem_papel(array['gestor', 'operador']));

-- 4. Normaliza os endpoints antigos: durante a transicao somente anon mantem
--    SELECT direto. Usuarios autenticados devem passar pelos wrappers abaixo.
revoke all privileges on table
  public.painel_resumo_mensal,
  public.painel_composicao_despesa,
  public.painel_saldo_fim_mes,
  public.painel_saldo_atual,
  public.painel_margem_contribuicao,
  public.painel_ultima_carga,
  public.painel_cargas,
  public.painel_diario,
  public.painel_recebimento_resumo,
  public.painel_recebimento_canal,
  public.painel_recebimento_hora,
  public.painel_fluxo_caixa,
  public.recebimento_conhecido,
  public.recebimento_projetado,
  public.projecao_despesa_fixa,
  public.projecao_despesa_direta,
  public.painel_saldo_por_conta,
  public.painel_dre_cascata,
  public.mv_despesa_mensal
from public, anon, authenticated;

grant select on table
  public.painel_resumo_mensal,
  public.painel_composicao_despesa,
  public.painel_saldo_fim_mes,
  public.painel_saldo_atual,
  public.painel_margem_contribuicao,
  public.painel_ultima_carga,
  public.painel_cargas,
  public.painel_diario,
  public.painel_recebimento_resumo,
  public.painel_recebimento_canal,
  public.painel_recebimento_hora,
  public.painel_fluxo_caixa,
  public.recebimento_conhecido,
  public.recebimento_projetado,
  public.projecao_despesa_fixa,
  public.projecao_despesa_direta,
  public.painel_saldo_por_conta,
  public.painel_dre_cascata,
  public.mv_despesa_mensal
to anon;

-- Categoria passa a ser acessivel somente pelo wrapper autenticado.
revoke all privileges on table public.categoria_dre
  from public, anon, authenticated;
drop policy if exists "leitura publica categoria_dre" on public.categoria_dre;

-- 5. Wrappers dos dashboards. security_barrier impede que filtros fornecidos
--    pelo cliente sejam empurrados abaixo da verificacao do papel.
create or replace view public.app_painel_resumo_mensal
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_resumo_mensal s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_composicao_despesa
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_composicao_despesa s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_saldo_fim_mes
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_saldo_fim_mes s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_saldo_atual
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_saldo_atual s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_margem_contribuicao
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_margem_contribuicao s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_ultima_carga
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_ultima_carga s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_cargas
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_cargas s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_diario
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_diario s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_recebimento_resumo
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_recebimento_resumo s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_recebimento_canal
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_recebimento_canal s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_recebimento_hora
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_recebimento_hora s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_fluxo_caixa
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_fluxo_caixa s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_recebimento_conhecido
with (security_barrier = true, security_invoker = false) as
select s.* from public.recebimento_conhecido s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_recebimento_projetado
with (security_barrier = true, security_invoker = false) as
select s.* from public.recebimento_projetado s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_projecao_despesa_fixa
with (security_barrier = true, security_invoker = false) as
select s.* from public.projecao_despesa_fixa s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_projecao_despesa_direta
with (security_barrier = true, security_invoker = false) as
select s.* from public.projecao_despesa_direta s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_saldo_por_conta
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_saldo_por_conta s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_painel_dre_cascata
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_dre_cascata s
where public.usuario_tem_papel(array['gestor']);

create or replace view public.app_mv_despesa_mensal
with (security_barrier = true, security_invoker = false) as
select s.* from public.mv_despesa_mensal s
where public.usuario_tem_papel(array['gestor']);

-- 6. Wrappers operacionais para gestor e operador.
create or replace view public.app_analise_individual
with (security_barrier = true, security_invoker = false) as
select s.* from public.analise_individual s
where public.usuario_tem_papel(array['gestor', 'operador']);

create or replace view public.app_excecoes
with (security_barrier = true, security_invoker = false) as
select s.* from public.excecoes s
where public.usuario_tem_papel(array['gestor', 'operador']);

create or replace view public.app_categoria_dre
with (security_barrier = true, security_invoker = false) as
select s.* from public.categoria_dre s
where public.usuario_tem_papel(array['gestor', 'operador']);

-- 7. Somente authenticated pode consultar os wrappers.
revoke all privileges on table
  public.app_painel_resumo_mensal,
  public.app_painel_composicao_despesa,
  public.app_painel_saldo_fim_mes,
  public.app_painel_saldo_atual,
  public.app_painel_margem_contribuicao,
  public.app_painel_ultima_carga,
  public.app_painel_cargas,
  public.app_painel_diario,
  public.app_painel_recebimento_resumo,
  public.app_painel_recebimento_canal,
  public.app_painel_recebimento_hora,
  public.app_painel_fluxo_caixa,
  public.app_recebimento_conhecido,
  public.app_recebimento_projetado,
  public.app_projecao_despesa_fixa,
  public.app_projecao_despesa_direta,
  public.app_painel_saldo_por_conta,
  public.app_painel_dre_cascata,
  public.app_mv_despesa_mensal,
  public.app_analise_individual,
  public.app_excecoes,
  public.app_categoria_dre
from public, anon, authenticated;

grant select on table
  public.app_painel_resumo_mensal,
  public.app_painel_composicao_despesa,
  public.app_painel_saldo_fim_mes,
  public.app_painel_saldo_atual,
  public.app_painel_margem_contribuicao,
  public.app_painel_ultima_carga,
  public.app_painel_cargas,
  public.app_painel_diario,
  public.app_painel_recebimento_resumo,
  public.app_painel_recebimento_canal,
  public.app_painel_recebimento_hora,
  public.app_painel_fluxo_caixa,
  public.app_recebimento_conhecido,
  public.app_recebimento_projetado,
  public.app_projecao_despesa_fixa,
  public.app_projecao_despesa_direta,
  public.app_painel_saldo_por_conta,
  public.app_painel_dre_cascata,
  public.app_mv_despesa_mensal,
  public.app_analise_individual,
  public.app_excecoes,
  public.app_categoria_dre
to authenticated;
