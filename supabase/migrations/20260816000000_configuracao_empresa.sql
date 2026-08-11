-- Configuracao de identidade para reutilizar o painel em outra empresa.
-- Nao altera dados financeiros, views app_*, permissoes existentes ou calculos.

create table if not exists public.configuracao_empresa (
  singleton boolean primary key default true check (singleton),
  nome text not null check (char_length(btrim(nome)) between 2 and 80),
  subtitulo text not null check (char_length(btrim(subtitulo)) between 2 and 100),
  atualizado_por uuid,
  atualizado_em timestamptz not null default now()
);

alter table public.configuracao_empresa enable row level security;

drop policy if exists configuracao_empresa_leitura_publica on public.configuracao_empresa;
create policy configuracao_empresa_leitura_publica
on public.configuracao_empresa
for select
to anon, authenticated
using (singleton = true);

insert into public.configuracao_empresa (singleton, nome, subtitulo)
values (true, 'Sir Fisher', 'Painel de Gestão')
on conflict (singleton) do nothing;

create table if not exists private.configuracao_empresa_historico (
  id bigint generated always as identity primary key,
  nome_anterior text not null,
  subtitulo_anterior text not null,
  nome_novo text not null,
  subtitulo_novo text not null,
  alterado_por uuid,
  alterado_em timestamptz not null default now()
);

alter table private.configuracao_empresa_historico enable row level security;

create index if not exists configuracao_empresa_historico_alterado_em_idx
  on private.configuracao_empresa_historico (alterado_em desc);

create or replace function public.app_configuracao_empresa()
returns table (nome text, subtitulo text)
language sql
stable
security invoker
set search_path = pg_catalog, pg_temp
as $$
  select c.nome, c.subtitulo
  from public.configuracao_empresa c
  where c.singleton = true;
$$;

create or replace function public.admin_obter_configuracao_empresa()
returns table (nome text, subtitulo text, atualizado_em timestamptz)
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem ver a configuracao da empresa.';
  end if;
  return query
  select c.nome, c.subtitulo, c.atualizado_em
  from public.configuracao_empresa c
  where c.singleton = true;
end;
$$;

create or replace function public.admin_salvar_configuracao_empresa(
  p_nome text,
  p_subtitulo text
)
returns table (nome text, subtitulo text, atualizado_em timestamptz)
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_anterior public.configuracao_empresa;
  v_nome text := btrim(coalesce(p_nome, ''));
  v_subtitulo text := btrim(coalesce(p_subtitulo, ''));
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem alterar a configuracao da empresa.';
  end if;
  if char_length(v_nome) not between 2 and 80 then
    raise exception using errcode = '22023', message = 'O nome deve ter entre 2 e 80 caracteres.';
  end if;
  if char_length(v_subtitulo) not between 2 and 100 then
    raise exception using errcode = '22023', message = 'O subtitulo deve ter entre 2 e 100 caracteres.';
  end if;

  select * into v_anterior
  from public.configuracao_empresa
  where singleton = true
  for update;

  if not found then
    raise exception using errcode = '55000', message = 'Configuracao da empresa nao inicializada.';
  end if;

  if (v_anterior.nome, v_anterior.subtitulo) is distinct from (v_nome, v_subtitulo) then
    insert into private.configuracao_empresa_historico (
      nome_anterior, subtitulo_anterior, nome_novo, subtitulo_novo, alterado_por
    ) values (
      v_anterior.nome, v_anterior.subtitulo, v_nome, v_subtitulo, auth.uid()
    );
  end if;

  return query
  update public.configuracao_empresa c
  set nome = v_nome,
      subtitulo = v_subtitulo,
      atualizado_por = auth.uid(),
      atualizado_em = now()
  where c.singleton = true
  returning c.nome, c.subtitulo, c.atualizado_em;
end;
$$;

revoke all privileges on table public.configuracao_empresa from public, anon, authenticated;
revoke all privileges on table private.configuracao_empresa_historico from public, anon, authenticated;
grant select (nome, subtitulo) on table public.configuracao_empresa to anon, authenticated;

revoke all privileges on function public.app_configuracao_empresa() from public, anon, authenticated;
grant execute on function public.app_configuracao_empresa() to anon, authenticated;

revoke all privileges on function public.admin_obter_configuracao_empresa() from public, anon, authenticated;
grant execute on function public.admin_obter_configuracao_empresa() to authenticated;

revoke all privileges on function public.admin_salvar_configuracao_empresa(text, text) from public, anon, authenticated;
grant execute on function public.admin_salvar_configuracao_empresa(text, text) to authenticated;
