-- =====================================================================
-- Introduz o papel admin e reorganiza os acessos em 3 perfis
-- =====================================================================
--
-- MODELO DE PAPEIS
--   admin    -> acesso irrestrito, incluindo administracao do site
--               (gestao de usuarios e status tecnico das cargas);
--   gestor   -> todos os dashboards financeiros e as rotinas
--               operacionais, sem acesso a administracao do site;
--   operador -> apenas as rotinas operacionais (classificacao,
--               analise individual e venda em especie).
--
-- Esta migration nao cria nenhum admin. Logo apos o deploy, ninguem
-- possui o papel admin: e necessario promover manualmente o primeiro
-- admin com um UPDATE direto no SQL Editor do Supabase (fora desta
-- migration, para nao versionar e-mail pessoal em texto claro):
--
--   update public.perfil_usuario
--   set papel = 'admin'
--   where user_id = (select id from auth.users where lower(email) = lower('<SEU_EMAIL_GOOGLE>'));
--
-- Ate esse passo manual ser feito, a tela de usuarios e a de status
-- ficam inacessiveis, pois ambas exigem o papel admin.
-- =====================================================================

begin;

-- 1. Amplia a constraint de papel para aceitar 'admin'.
alter table public.perfil_usuario drop constraint perfil_usuario_papel_check;
alter table public.perfil_usuario
  add constraint perfil_usuario_papel_check check (papel in ('admin', 'gestor', 'operador'));

-- 2. Dashboards financeiros: passam a aceitar admin e gestor.
create or replace view public.app_painel_resumo_mensal
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_resumo_mensal s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_composicao_despesa
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_composicao_despesa s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_saldo_fim_mes
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_saldo_fim_mes s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_saldo_atual
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_saldo_atual s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_margem_contribuicao
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_margem_contribuicao s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_ultima_carga
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_ultima_carga s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_cargas
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_cargas s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_diario
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_diario s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_recebimento_resumo
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_recebimento_resumo s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_recebimento_canal
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_recebimento_canal s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_recebimento_hora
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_recebimento_hora s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_fluxo_caixa
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_fluxo_caixa s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_recebimento_conhecido
with (security_barrier = true, security_invoker = false) as
select s.* from public.recebimento_conhecido s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_recebimento_projetado
with (security_barrier = true, security_invoker = false) as
select s.* from public.recebimento_projetado s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_projecao_despesa_fixa
with (security_barrier = true, security_invoker = false) as
select s.* from public.projecao_despesa_fixa s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_projecao_despesa_direta
with (security_barrier = true, security_invoker = false) as
select s.* from public.projecao_despesa_direta s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_saldo_por_conta
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_saldo_por_conta s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_painel_dre_cascata
with (security_barrier = true, security_invoker = false) as
select s.* from public.painel_dre_cascata s
where public.usuario_tem_papel(array['admin', 'gestor']);

create or replace view public.app_mv_despesa_mensal
with (security_barrier = true, security_invoker = false) as
select s.* from public.mv_despesa_mensal s
where public.usuario_tem_papel(array['admin', 'gestor']);

-- 3. Rotinas operacionais: passam a aceitar admin, gestor e operador.
create or replace view public.app_analise_individual
with (security_barrier = true, security_invoker = false) as
select s.* from public.analise_individual s
where public.usuario_tem_papel(array['admin', 'gestor', 'operador']);

create or replace view public.app_excecoes
with (security_barrier = true, security_invoker = false) as
select s.* from public.excecoes s
where public.usuario_tem_papel(array['admin', 'gestor', 'operador']);

create or replace view public.app_categoria_dre
with (security_barrier = true, security_invoker = false) as
select s.* from public.categoria_dre s
where public.usuario_tem_papel(array['admin', 'gestor', 'operador']);

drop policy if exists ajuste_auth_sel on public.ajuste_manual;
drop policy if exists ajuste_auth_ins on public.ajuste_manual;
drop policy if exists ajuste_auth_upd on public.ajuste_manual;

create policy ajuste_auth_sel
  on public.ajuste_manual
  for select
  to authenticated
  using (public.usuario_tem_papel(array['admin', 'gestor', 'operador']));

create policy ajuste_auth_ins
  on public.ajuste_manual
  for insert
  to authenticated
  with check (public.usuario_tem_papel(array['admin', 'gestor', 'operador']));

create policy ajuste_auth_upd
  on public.ajuste_manual
  for update
  to authenticated
  using (public.usuario_tem_papel(array['admin', 'gestor', 'operador']))
  with check (public.usuario_tem_papel(array['admin', 'gestor', 'operador']));

drop policy if exists de_para_auth_ins on public.de_para;
create policy de_para_auth_ins
  on public.de_para
  for insert
  to authenticated
  with check (public.usuario_tem_papel(array['admin', 'gestor', 'operador']));

drop policy if exists venda_especie_auth_sel on public.venda_especie;
drop policy if exists venda_especie_auth_ins on public.venda_especie;
drop policy if exists venda_especie_auth_upd on public.venda_especie;

create policy venda_especie_auth_sel
  on public.venda_especie
  for select
  to authenticated
  using (public.usuario_tem_papel(array['admin', 'gestor', 'operador']));

create policy venda_especie_auth_ins
  on public.venda_especie
  for insert
  to authenticated
  with check (public.usuario_tem_papel(array['admin', 'gestor', 'operador']));

create policy venda_especie_auth_upd
  on public.venda_especie
  for update
  to authenticated
  using (public.usuario_tem_papel(array['admin', 'gestor', 'operador']))
  with check (public.usuario_tem_papel(array['admin', 'gestor', 'operador']));

-- 4. Conciliacao e planejamento: informacao do negocio, admin e gestor.
create or replace function private.ler_conciliacao_stone_resumo()
returns setof public.conciliacao_stone_resumo
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select c.* from public.conciliacao_stone_resumo c
  where public.usuario_tem_papel(array['admin', 'gestor']::text[]);
$$;

create or replace function private.ler_conciliacao_stone()
returns setof public.conciliacao_stone
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select c.* from public.conciliacao_stone c
  where public.usuario_tem_papel(array['admin', 'gestor']::text[]);
$$;

create or replace function private.ler_painel_meta_real_mensal()
returns setof public.painel_meta_real_mensal
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select m.* from public.painel_meta_real_mensal m
  where public.usuario_tem_papel(array['admin', 'gestor']::text[]);
$$;

-- 5. Status do site (ex-qualidade das cargas): exclusivo do admin.
create or replace function private.ler_status_cargas()
returns table (
  fonte text,
  linhas bigint,
  periodo_inicio date,
  periodo_fim date,
  ultima_importacao timestamptz,
  ultima_carga timestamptz,
  atraso_dias integer,
  situacao text
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  with bases as (
    select 'Extrato Stone'::text fonte, count(*)::bigint linhas,
           min(e.data_hora)::date periodo_inicio, max(e.data_hora)::date periodo_fim,
           max(e.importado_em) ultima_importacao
    from public.raw_stone_extrato e
    union all
    select 'Vendas Stone', count(*)::bigint,
           min(v.data_venda)::date, max(v.data_venda)::date, max(v.importado_em)
    from public.raw_stone_vendas v
    union all
    select 'Recebíveis Stone', count(*)::bigint,
           min(coalesce(r.data_vencimento, r.data_venda::date)),
           max(coalesce(r.data_vencimento, r.data_venda::date)), max(r.importado_em)
    from public.raw_stone_recebiveis r
    union all
    select 'Extrato BB', count(*)::bigint,
           min(b.data), max(b.data), max(b.importado_em)
    from public.raw_bb b
  ), logs as (
    select l.fontes fonte, max(l.data_hora) ultima_carga
    from public.log_carga l
    group by l.fontes
  )
  select
    b.fonte,
    b.linhas,
    b.periodo_inicio,
    b.periodo_fim,
    b.ultima_importacao,
    l.ultima_carga,
    case when b.ultima_importacao is null then null
         else greatest(current_date - b.ultima_importacao::date, 0) end::integer,
    case
      when b.ultima_importacao is null then 'sem carga'
      when current_date - b.ultima_importacao::date <= 2 then 'em dia'
      when current_date - b.ultima_importacao::date <= 5 then 'atenção'
      else 'atrasada'
    end::text
  from bases b
  left join logs l on l.fonte = b.fonte
  where public.usuario_tem_papel(array['admin']::text[])
  order by b.fonte;
$$;

revoke all privileges on function private.ler_status_cargas() from public, anon, authenticated;
grant execute on function private.ler_status_cargas() to authenticated;

create or replace view public.app_status_cargas
with (security_barrier = true, security_invoker = true) as
select * from private.ler_status_cargas();

revoke all privileges on table public.app_status_cargas from public, anon, authenticated;
grant select on table public.app_status_cargas to authenticated;

drop view if exists public.app_qualidade_cargas;
drop function if exists private.ler_qualidade_cargas();

-- 6. Gestao de usuarios: exclusiva do admin.
create or replace function private.ler_usuarios_acesso()
returns table (
  user_id uuid,
  email text,
  nome text,
  criado_em timestamptz,
  ultimo_login timestamptz,
  papel text,
  ativo boolean
)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select
    u.id,
    u.email::text,
    coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name')::text,
    u.created_at,
    u.last_sign_in_at,
    p.papel,
    coalesce(p.ativo, false)
  from auth.users u
  left join public.perfil_usuario p on p.user_id = u.id
  where public.usuario_tem_papel(array['admin']::text[])
  order by u.created_at desc;
$$;

create or replace function public.definir_acesso_usuario(
  p_user_id uuid,
  p_papel text,
  p_ativo boolean default true
)
returns table (user_id uuid, email text, papel text, ativo boolean)
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_papel_atual text;
  v_ativo_atual boolean;
  v_admins_ativos integer;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem alterar acessos.';
  end if;

  if p_papel is null or p_papel not in ('admin', 'gestor', 'operador') then
    raise exception using errcode = '22023', message = 'Papel invalido.';
  end if;

  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception using errcode = '22023', message = 'Usuario nao encontrado.';
  end if;

  lock table public.perfil_usuario in share row exclusive mode;

  select p.papel, p.ativo
    into v_papel_atual, v_ativo_atual
  from public.perfil_usuario p
  where p.user_id = p_user_id;

  if v_papel_atual = 'admin'
     and v_ativo_atual
     and (p_papel <> 'admin' or not p_ativo) then
    select count(*)::integer
      into v_admins_ativos
    from public.perfil_usuario p
    where p.papel = 'admin' and p.ativo;

    if v_admins_ativos <= 1 then
      raise exception using errcode = '23514', message = 'Nao e possivel remover o ultimo administrador ativo.';
    end if;
  end if;

  insert into public.perfil_usuario (user_id, papel, ativo)
  values (p_user_id, p_papel, p_ativo)
  on conflict on constraint perfil_usuario_pkey do update
    set papel = excluded.papel,
        ativo = excluded.ativo;

  return query
  select u.id, u.email::text, p.papel, p.ativo
  from auth.users u
  join public.perfil_usuario p on p.user_id = u.id
  where u.id = p_user_id;
end;
$$;

revoke all privileges on function private.ler_usuarios_acesso() from public, anon, authenticated;
revoke all privileges on function public.definir_acesso_usuario(uuid, text, boolean) from public, anon, authenticated;
grant execute on function private.ler_usuarios_acesso() to authenticated;
grant execute on function public.definir_acesso_usuario(uuid, text, boolean) to authenticated;

commit;
