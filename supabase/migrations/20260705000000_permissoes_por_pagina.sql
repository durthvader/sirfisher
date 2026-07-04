-- =====================================================================
-- Permissoes de pagina configuraveis por gestor/operador
-- =====================================================================
--
-- Ate aqui, quais paginas cada papel via era fixo no codigo (auth.js).
-- Esta migration cria uma tabela editavel pelo admin, pela tela
-- permissoes.html, para decidir pagina a pagina se gestor e/ou operador
-- podem acessa-la.
--
-- Duas invariantes de seguranca, mantidas fora desta tabela:
--   - admin sempre tem acesso irrestrito, independente do conteudo aqui;
--   - usuarios.html, status.html e a propria permissoes.html continuam
--     travadas ao admin no codigo (assets/auth.js), nao aparecem aqui e
--     nao podem ser tornadas acessiveis a gestor/operador por esta via.
--
-- O seed abaixo reproduz o mapeamento atual, entao aplicar esta migration
-- nao muda nenhum acesso existente ate o admin editar algo em
-- permissoes.html.
-- =====================================================================

begin;

create table public.pagina_permissao (
  pagina text primary key,
  papeis text[] not null default '{}',
  atualizado_em timestamptz not null default now()
);

alter table public.pagina_permissao enable row level security;

revoke all privileges on table public.pagina_permissao from public, anon;
grant select on table public.pagina_permissao to authenticated;

drop policy if exists pagina_permissao_leitura on public.pagina_permissao;
create policy pagina_permissao_leitura
  on public.pagina_permissao
  for select
  to authenticated
  using (true);

insert into public.pagina_permissao (pagina, papeis) values
  ('index.html', array['gestor']),
  ('vendas.html', array['gestor']),
  ('caixa.html', array['gestor']),
  ('dre.html', array['gestor']),
  ('despesas.html', array['gestor']),
  ('conciliacao.html', array['gestor']),
  ('planejamento.html', array['gestor']),
  ('rotinas.html', array['gestor', 'operador']),
  ('analise_individual.html', array['gestor', 'operador']),
  ('classificar_excecoes.html', array['gestor', 'operador']),
  ('venda_especie.html', array['gestor', 'operador'])
on conflict (pagina) do nothing;

create or replace function public.definir_permissao_pagina(
  p_pagina text,
  p_papeis text[]
)
returns table (pagina text, papeis text[])
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_papeis_validos text[] := array['gestor', 'operador'];
  v_pagina_valida boolean;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem alterar permissoes.';
  end if;

  select exists(select 1 from public.pagina_permissao pp where pp.pagina = p_pagina)
    into v_pagina_valida;

  if not v_pagina_valida then
    raise exception using errcode = '22023', message = 'Pagina desconhecida.';
  end if;

  if p_papeis is null or not (p_papeis <@ v_papeis_validos) then
    raise exception using errcode = '22023', message = 'Papel invalido. Use apenas gestor e/ou operador.';
  end if;

  update public.pagina_permissao pp
  set papeis = p_papeis, atualizado_em = now()
  where pp.pagina = p_pagina;

  return query
  select pp.pagina, pp.papeis
  from public.pagina_permissao pp
  where pp.pagina = p_pagina;
end;
$$;

revoke all privileges on function public.definir_permissao_pagina(text, text[]) from public, anon, authenticated;
grant execute on function public.definir_permissao_pagina(text, text[]) to authenticated;

commit;
