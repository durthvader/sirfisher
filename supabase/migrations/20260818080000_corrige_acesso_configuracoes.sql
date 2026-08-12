-- Corrige os contratos de leitura das configuracoes consumidas pelo front-end.
-- Nao altera valores de parametros, identidade da empresa ou fatos financeiros.

begin;

-- As views financeiras autenticadas usam esta auxiliar, mas os papeis da Data
-- API nao devem receber SELECT direto no catalogo administrativo de parametros.
-- O search_path fechado e a referencia qualificada limitam o SECURITY DEFINER
-- a uma unica leitura numerica por chave.
create or replace function public.parametro_valor(p_chave text, p_padrao numeric)
returns numeric
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select coalesce(
    (select p.valor from public.parametros p where p.chave = p_chave),
    p_padrao
  );
$$;

revoke all privileges on table public.parametros from public, anon, authenticated;
revoke all privileges on function public.parametro_valor(text, numeric)
  from public, anon, authenticated;
grant execute on function public.parametro_valor(text, numeric) to authenticated;

comment on function public.parametro_valor(text, numeric) is
  'Le um parametro numerico sem expor acesso direto ao catalogo public.parametros.';

do $migration$
begin
  if exists (
    select 1 from pg_roles where rolname = 'supabase_read_only_user'
  ) then
    grant execute on function public.parametro_valor(text, numeric)
      to supabase_read_only_user;
  end if;
end;
$migration$;

-- A tabela tem no maximo uma linha valida (PK + CHECK singleton). A policy RLS
-- continua filtrando essa linha; retirar singleton do SELECT evita exigir ao
-- navegador privilegio de coluna que ele nao precisa possuir.
create or replace function public.app_configuracao_empresa()
returns table (nome text, subtitulo text)
language sql
stable
security invoker
set search_path = pg_catalog, pg_temp
as $$
  select c.nome, c.subtitulo
  from public.configuracao_empresa c
  limit 1;
$$;

revoke all privileges on function public.app_configuracao_empresa()
  from public, anon, authenticated;
grant execute on function public.app_configuracao_empresa() to anon, authenticated;

comment on function public.app_configuracao_empresa() is
  'Entrega nome e subtitulo publicos sem exigir acesso a colunas administrativas.';

-- Contratos que evitam reintroduzir a exposicao direta que causou a regressao.
do $validation$
declare
  v_parametro_definer boolean;
  v_empresa_definer boolean;
begin
  select p.prosecdef
    into v_parametro_definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'parametro_valor'
    and p.proargtypes = '25 1700'::oidvector;

  select p.prosecdef
    into v_empresa_definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'app_configuracao_empresa'
    and p.pronargs = 0;

  if v_parametro_definer is distinct from true then
    raise exception 'parametro_valor deve permanecer SECURITY DEFINER';
  end if;
  if v_empresa_definer is distinct from false then
    raise exception 'app_configuracao_empresa deve permanecer SECURITY INVOKER';
  end if;
  if has_column_privilege('anon', 'public.parametros', 'valor', 'SELECT')
     or has_column_privilege('authenticated', 'public.parametros', 'valor', 'SELECT') then
    raise exception 'parametros nao pode ter leitura direta pela Data API';
  end if;
  if not has_column_privilege('anon', 'public.configuracao_empresa', 'nome', 'SELECT')
     or not has_column_privilege('authenticated', 'public.configuracao_empresa', 'subtitulo', 'SELECT') then
    raise exception 'colunas publicas da identidade perderam permissao de leitura';
  end if;
end;
$validation$;

commit;
