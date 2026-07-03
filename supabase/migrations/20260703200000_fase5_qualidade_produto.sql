-- =====================================================================
-- Fase 5: gestão de acessos, qualidade, conciliação e metas
-- =====================================================================
--
-- Objetos criados:
--   - app_usuarios_acesso: usuários do Auth e respectivos papéis;
--   - definir_acesso_usuario(): upsert de papel, somente para gestor;
--   - app_qualidade_cargas: cobertura e atraso das quatro fontes regulares;
--   - app_conciliacao_stone_resumo e app_conciliacao_stone;
--   - app_painel_meta_real_mensal.
--
-- Segurança:
--   Toda leitura privilegiada passa por funções no schema private, com
--   search_path fixo e validação explícita do papel gestor. A função de escrita
--   protege o último gestor ativo contra desativação ou rebaixamento.
--
-- Esta migration não altera dados financeiros e não tenta conciliar banco por
-- aproximação de data/valor, pois não existe uma chave bancária confirmada.
-- =====================================================================

begin;

create schema if not exists private;
revoke all privileges on schema private from public, anon;
grant usage on schema private to authenticated;

-- Evita reavaliação de auth.uid() a cada linha da policy existente.
drop policy if exists perfil_usuario_le_proprio on public.perfil_usuario;
create policy perfil_usuario_le_proprio
  on public.perfil_usuario
  for select
  to authenticated
  using (user_id = (select auth.uid()));

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
  where public.usuario_tem_papel(array['gestor']::text[])
  order by u.created_at desc;
$$;

create or replace function public.definir_acesso_usuario(
  p_user_id uuid,
  p_papel text,
  p_ativo boolean default true
)
returns table (
  user_id uuid,
  email text,
  papel text,
  ativo boolean
)
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_papel_atual text;
  v_ativo_atual boolean;
  v_gestores_ativos integer;
begin
  if not public.usuario_tem_papel(array['gestor']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas gestores podem alterar acessos.';
  end if;

  if p_papel is null or p_papel not in ('gestor', 'operador') then
    raise exception using errcode = '22023', message = 'Papel inválido.';
  end if;

  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception using errcode = '22023', message = 'Usuário não encontrado.';
  end if;

  lock table public.perfil_usuario in share row exclusive mode;

  select p.papel, p.ativo
    into v_papel_atual, v_ativo_atual
  from public.perfil_usuario p
  where p.user_id = p_user_id;

  if v_papel_atual = 'gestor'
     and v_ativo_atual
     and (p_papel <> 'gestor' or not p_ativo) then
    select count(*)::integer
      into v_gestores_ativos
    from public.perfil_usuario p
    where p.papel = 'gestor' and p.ativo;

    if v_gestores_ativos <= 1 then
      raise exception using errcode = '23514', message = 'Não é possível remover o último gestor ativo.';
    end if;
  end if;

  insert into public.perfil_usuario (user_id, papel, ativo)
  values (p_user_id, p_papel, p_ativo)
  on conflict (user_id) do update
    set papel = excluded.papel,
        ativo = excluded.ativo;

  return query
  select u.id, u.email::text, p.papel, p.ativo
  from auth.users u
  join public.perfil_usuario p on p.user_id = u.id
  where u.id = p_user_id;
end;
$$;

create or replace function private.ler_qualidade_cargas()
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
  where public.usuario_tem_papel(array['gestor']::text[])
  order by b.fonte;
$$;

create or replace function private.ler_conciliacao_stone_resumo()
returns setof public.conciliacao_stone_resumo
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select c.* from public.conciliacao_stone_resumo c
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_conciliacao_stone()
returns setof public.conciliacao_stone
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select c.* from public.conciliacao_stone c
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

create or replace function private.ler_painel_meta_real_mensal()
returns setof public.painel_meta_real_mensal
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $$
  select m.* from public.painel_meta_real_mensal m
  where public.usuario_tem_papel(array['gestor']::text[]);
$$;

revoke all privileges on function private.ler_usuarios_acesso() from public, anon, authenticated;
revoke all privileges on function private.ler_qualidade_cargas() from public, anon, authenticated;
revoke all privileges on function private.ler_conciliacao_stone_resumo() from public, anon, authenticated;
revoke all privileges on function private.ler_conciliacao_stone() from public, anon, authenticated;
revoke all privileges on function private.ler_painel_meta_real_mensal() from public, anon, authenticated;
revoke all privileges on function public.definir_acesso_usuario(uuid, text, boolean) from public, anon, authenticated;

grant execute on function private.ler_usuarios_acesso() to authenticated;
grant execute on function private.ler_qualidade_cargas() to authenticated;
grant execute on function private.ler_conciliacao_stone_resumo() to authenticated;
grant execute on function private.ler_conciliacao_stone() to authenticated;
grant execute on function private.ler_painel_meta_real_mensal() to authenticated;
grant execute on function public.definir_acesso_usuario(uuid, text, boolean) to authenticated;

create or replace view public.app_usuarios_acesso
with (security_barrier = true, security_invoker = true) as
select * from private.ler_usuarios_acesso();

create or replace view public.app_qualidade_cargas
with (security_barrier = true, security_invoker = true) as
select * from private.ler_qualidade_cargas();

create or replace view public.app_conciliacao_stone_resumo
with (security_barrier = true, security_invoker = true) as
select * from private.ler_conciliacao_stone_resumo();

create or replace view public.app_conciliacao_stone
with (security_barrier = true, security_invoker = true) as
select * from private.ler_conciliacao_stone();

create or replace view public.app_painel_meta_real_mensal
with (security_barrier = true, security_invoker = true) as
select * from private.ler_painel_meta_real_mensal();

revoke all privileges on table
  public.app_usuarios_acesso,
  public.app_qualidade_cargas,
  public.app_conciliacao_stone_resumo,
  public.app_conciliacao_stone,
  public.app_painel_meta_real_mensal
from public, anon, authenticated;

grant select on table
  public.app_usuarios_acesso,
  public.app_qualidade_cargas,
  public.app_conciliacao_stone_resumo,
  public.app_conciliacao_stone,
  public.app_painel_meta_real_mensal
to authenticated;

commit;
