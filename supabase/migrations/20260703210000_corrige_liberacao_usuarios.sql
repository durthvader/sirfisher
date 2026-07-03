-- Corrige a liberacao de usuarios na RPC administrativa.
-- ON CONFLICT (user_id) era ambiguo porque user_id tambem e coluna de saida.

begin;

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
  v_gestores_ativos integer;
begin
  if not public.usuario_tem_papel(array['gestor']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas gestores podem alterar acessos.';
  end if;

  if p_papel is null or p_papel not in ('gestor', 'operador') then
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

  if v_papel_atual = 'gestor'
     and v_ativo_atual
     and (p_papel <> 'gestor' or not p_ativo) then
    select count(*)::integer
      into v_gestores_ativos
    from public.perfil_usuario p
    where p.papel = 'gestor' and p.ativo;

    if v_gestores_ativos <= 1 then
      raise exception using errcode = '23514', message = 'Nao e possivel remover o ultimo gestor ativo.';
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

revoke all privileges on function public.definir_acesso_usuario(uuid, text, boolean)
  from public, anon, authenticated;
grant execute on function public.definir_acesso_usuario(uuid, text, boolean)
  to authenticated;

commit;
