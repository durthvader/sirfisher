-- Nomes de usuario vem do perfil Google (raw_user_meta_data.full_name/name)
-- e chegam com capitalizacao inconsistente (ex.: "renan torres",
-- "HEMILE ALEXANDRE"). Aplica Title Case so na exibicao (initcap), sem
-- tocar no dado bruto em auth.users - assim nao ha risco de o proximo
-- login via Google reverter a mudanca, e a regra vale automaticamente
-- para qualquer usuario, atual ou futuro.

begin;

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
    initcap(coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name'))::text,
    u.created_at,
    u.last_sign_in_at,
    p.papel,
    coalesce(p.ativo, false)
  from auth.users u
  left join public.perfil_usuario p on p.user_id = u.id
  where public.usuario_tem_papel(array['admin']::text[])
  order by u.created_at desc;
$$;

create or replace view public.app_venda_especie_controle
with (security_barrier = true, security_invoker = false) as
select
  v.id,
  v.data,
  v.unidade,
  v.valor,
  v.observacao,
  v.criado_em,
  v.recolhida_em,
  v.depositada_em,
  initcap(coalesce(uc.raw_user_meta_data ->> 'full_name', uc.raw_user_meta_data ->> 'name'))::text as cadastrado_por_nome,
  initcap(coalesce(ur.raw_user_meta_data ->> 'full_name', ur.raw_user_meta_data ->> 'name'))::text as recolhida_por_nome,
  initcap(coalesce(ud.raw_user_meta_data ->> 'full_name', ud.raw_user_meta_data ->> 'name'))::text as depositada_por_nome
from public.venda_especie v
left join auth.users uc on uc.id = v.cadastrado_por
left join auth.users ur on ur.id = v.recolhida_por
left join auth.users ud on ud.id = v.depositada_por
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

commit;
