-- Permite que as duas RPCs de configuracao explicitamente publicas funcionem
-- antes do login. USAGE no schema nao concede privilegios de objeto; ele torna
-- utilizaveis apenas os grants anonimos ja revisados abaixo.

begin;

grant usage on schema public to anon;

-- A unidade ja integra app_configuracao_operacional(), que executa como dono.
-- Nao ha necessidade de expor a auxiliar de baixo nivel diretamente ao anon.
revoke all privileges on function public.unidade_principal_nome() from anon;

revoke all privileges on function public.app_configuracao_empresa() from anon;
grant execute on function public.app_configuracao_empresa() to anon;

revoke all privileges on function public.app_configuracao_operacional() from anon;
grant execute on function public.app_configuracao_operacional() to anon;

do $validation$
begin
  if not has_schema_privilege('anon', 'public', 'USAGE') then
    raise exception 'anon precisa de USAGE para chamar as configuracoes publicas';
  end if;
  if not has_function_privilege('anon', 'public.app_configuracao_empresa()', 'EXECUTE')
     or not has_function_privilege('anon', 'public.app_configuracao_operacional()', 'EXECUTE') then
    raise exception 'RPCs publicas de configuracao perderam EXECUTE';
  end if;
  if has_function_privilege('anon', 'public.parametro_valor(text,numeric)', 'EXECUTE')
     or has_function_privilege('anon', 'public.unidade_principal_nome()', 'EXECUTE') then
    raise exception 'anon recebeu acesso a uma auxiliar de baixo nivel';
  end if;
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(
      coalesce(
        c.relacl,
        acldefault(
          case when c.relkind = 'S' then 's'::"char" else 'r'::"char" end,
          c.relowner
        )
      )
    ) x
    left join pg_roles r on r.oid = x.grantee
    where n.nspname = 'public'
      and (x.grantee = 0 or r.rolname = 'anon')
  ) then
    raise exception 'USAGE nao pode ativar privilegios anonimos de tabela ou sequencia';
  end if;
  if exists (
    select 1
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(a.attacl) x
    left join pg_roles r on r.oid = x.grantee
    where n.nspname = 'public'
      and a.attnum > 0
      and not a.attisdropped
      and (x.grantee = 0 or r.rolname = 'anon')
      and not (
        r.rolname = 'anon'
        and c.relname = 'configuracao_empresa'
        and a.attname in ('nome', 'subtitulo')
        and x.privilege_type = 'SELECT'
      )
  ) then
    raise exception 'Somente nome e subtitulo podem ter SELECT anonimo por coluna';
  end if;
end;
$validation$;

commit;
