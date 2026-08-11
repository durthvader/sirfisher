-- Mantem o conector Supabase somente-leitura capaz de consultar as views que
-- usam a unidade principal e os parametros operacionais.

begin;

do $migration$
begin
  if exists (
    select 1 from pg_roles where rolname = 'supabase_read_only_user'
  ) then
    grant execute on function public.unidade_principal_nome()
      to supabase_read_only_user;
    grant execute on function public.parametro_valor(text, numeric)
      to supabase_read_only_user;
  end if;
end;
$migration$;

commit;
