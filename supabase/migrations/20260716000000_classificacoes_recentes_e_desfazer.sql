-- Classificacoes reversiveis sem criar tabela de historico.
--
-- A view reune o estado atual das regras por fornecedor e dos ajustes por
-- transacao. As RPCs centralizam inclusao, correcao e exclusao, validando o
-- papel autenticado e a categoria escolhida.

begin;

create or replace function public.classificar_excecao(
  p_chave_tipo text,
  p_chave_valor text,
  p_fornecedor text,
  p_categoria text
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id bigint;
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  if not exists (select 1 from public.categoria_dre c where c.categoria = p_categoria) then
    raise exception using errcode = '22023', message = 'Categoria invalida.';
  end if;

  insert into public.de_para (chave_tipo, chave_valor, fornecedor, categoria, atualizado_em)
  values (p_chave_tipo, p_chave_valor, p_fornecedor, p_categoria, now())
  returning id::bigint into v_id;

  return v_id;
end;
$function$;

create or replace function public.classificar_transacao(
  p_origem text,
  p_raw_id bigint,
  p_categoria text
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id bigint;
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  if not exists (select 1 from public.categoria_dre c where c.categoria = p_categoria) then
    raise exception using errcode = '22023', message = 'Categoria invalida.';
  end if;

  insert into public.ajuste_manual (origem, raw_id, categoria, criado_em)
  values (p_origem, p_raw_id, p_categoria, now())
  on conflict (origem, raw_id) do update
    set categoria = excluded.categoria,
        criado_em = now()
  returning id::bigint into v_id;

  return v_id;
end;
$function$;

create or replace function public.corrigir_classificacao(
  p_tipo text,
  p_id bigint,
  p_categoria text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_afetadas integer;
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  if not exists (select 1 from public.categoria_dre c where c.categoria = p_categoria) then
    raise exception using errcode = '22023', message = 'Categoria invalida.';
  end if;

  if p_tipo = 'excecao' then
    update public.de_para
       set categoria = p_categoria,
           atualizado_em = now()
     where id = p_id;
  elsif p_tipo = 'individual' then
    update public.ajuste_manual
       set categoria = p_categoria,
           criado_em = now()
     where id = p_id;
  else
    raise exception using errcode = '22023', message = 'Tipo de classificacao invalido.';
  end if;

  get diagnostics v_afetadas = row_count;
  if v_afetadas = 0 then
    raise exception using errcode = 'P0002', message = 'Classificacao nao encontrada.';
  end if;
end;
$function$;

create or replace function public.desfazer_classificacao(
  p_tipo text,
  p_id bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_afetadas integer;
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  if p_tipo = 'excecao' then
    delete from public.de_para where id = p_id;
  elsif p_tipo = 'individual' then
    delete from public.ajuste_manual where id = p_id;
  else
    raise exception using errcode = '22023', message = 'Tipo de classificacao invalido.';
  end if;

  get diagnostics v_afetadas = row_count;
  if v_afetadas = 0 then
    raise exception using errcode = 'P0002', message = 'Classificacao nao encontrada.';
  end if;
end;
$function$;

create or replace view public.app_classificacoes_recentes
with (security_barrier = true, security_invoker = false) as
select
  'excecao'::text as tipo,
  d.id::bigint as id,
  coalesce(d.fornecedor, d.chave_valor) as titulo,
  case d.chave_tipo when 'cnpj' then 'Regra por CNPJ' else 'Regra por nome' end as detalhe,
  d.categoria,
  c.natureza,
  d.atualizado_em as quando,
  null::date as data_lancamento,
  null::numeric as valor
from public.de_para d
left join public.categoria_dre c on c.categoria = d.categoria
where d.ativo
  and public.usuario_tem_papel(array['admin', 'socio', 'gerente'])

union all

select
  'individual'::text as tipo,
  a.id::bigint as id,
  coalesce(f.contraparte_nome, f.fornecedor, a.origem || ' #' || a.raw_id::text) as titulo,
  'Transacao individual'::text as detalhe,
  a.categoria,
  f.natureza,
  a.criado_em as quando,
  f.data_caixa as data_lancamento,
  f.valor
from public.ajuste_manual a
left join public.fato_financeiro f
  on f.origem = a.origem and f.raw_id = a.raw_id
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

revoke all privileges on function public.classificar_excecao(text, text, text, text) from public, anon;
revoke all privileges on function public.classificar_transacao(text, bigint, text) from public, anon;
revoke all privileges on function public.corrigir_classificacao(text, bigint, text) from public, anon;
revoke all privileges on function public.desfazer_classificacao(text, bigint) from public, anon;
grant execute on function public.classificar_excecao(text, text, text, text) to authenticated;
grant execute on function public.classificar_transacao(text, bigint, text) to authenticated;
grant execute on function public.corrigir_classificacao(text, bigint, text) to authenticated;
grant execute on function public.desfazer_classificacao(text, bigint) to authenticated;

revoke all privileges on public.app_classificacoes_recentes from public, anon;
grant select on public.app_classificacoes_recentes to authenticated;

commit;
