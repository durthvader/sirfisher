-- Auditoria das alteracoes feitas na tela de parametros gerais.
-- Nao altera valores, views, RLS existente ou regras de projecao.

create table if not exists private.parametro_historico (
  id bigint generated always as identity primary key,
  chave text not null,
  valor_anterior numeric not null,
  valor_novo numeric not null,
  alterado_por uuid,
  alterado_em timestamptz not null default now()
);

alter table private.parametro_historico enable row level security;

create index if not exists parametro_historico_chave_alterado_em_idx
  on private.parametro_historico (chave, alterado_em desc);

create or replace function public.admin_salvar_parametro(p_chave text, p_valor numeric)
returns public.parametros
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_anterior public.parametros;
  v_row public.parametros;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem alterar parametros.';
  end if;
  if p_valor is null then
    raise exception using errcode = '22023', message = 'Valor obrigatorio.';
  end if;

  select * into v_anterior from public.parametros where chave = p_chave for update;
  if not found then
    raise exception using errcode = '22023', message = 'Parametro desconhecido: ' || coalesce(p_chave, '(nulo)');
  end if;

  update public.parametros set valor = p_valor
  where chave = p_chave
  returning * into v_row;

  if v_anterior.valor is distinct from v_row.valor then
    insert into private.parametro_historico(chave, valor_anterior, valor_novo, alterado_por)
    values (v_row.chave, v_anterior.valor, v_row.valor, auth.uid());
  end if;

  return v_row;
end;
$$;

create or replace function public.admin_listar_historico_parametros(p_limite integer default 80)
returns table (
  chave text,
  valor_anterior numeric,
  valor_novo numeric,
  alterado_por uuid,
  alterado_em timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem ver o historico de parametros.';
  end if;
  return query
  select h.chave, h.valor_anterior, h.valor_novo, h.alterado_por, h.alterado_em
  from private.parametro_historico h
  order by h.alterado_em desc, h.id desc
  limit greatest(1, least(coalesce(p_limite, 80), 200));
end;
$$;

revoke all privileges on table private.parametro_historico from public, anon, authenticated;
revoke all privileges on function public.admin_salvar_parametro(text, numeric) from public, anon, authenticated;
grant execute on function public.admin_salvar_parametro(text, numeric) to authenticated;
revoke all privileges on function public.admin_listar_historico_parametros(integer) from public, anon, authenticated;
grant execute on function public.admin_listar_historico_parametros(integer) to authenticated;
