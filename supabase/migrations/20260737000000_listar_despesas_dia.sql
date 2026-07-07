-- Lista as despesas individuais de um dia para o detalhe do calendário.
-- Mesmos filtros da CTE despesas_reais de listar_calendario_financeiro
-- (data_caixa, Débito, entra_dre, empresas PRAIA/BB) para a soma bater
-- com a coluna Despesas. Carregada sob demanda pelo popover, para não
-- pesar o carregamento inicial da página.

begin;

create or replace function public.listar_despesas_dia(p_dia date)
returns table (
  descricao text,
  categoria text,
  valor numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_dia is null then
    raise exception using errcode = '22023', message = 'Dia invalido.';
  end if;

  return query
  select
    coalesce(
      nullif(btrim(f.fornecedor), ''),
      nullif(btrim(f.contraparte_nome), ''),
      f.categoria,
      'Sem descricao'
    ) as descricao,
    f.categoria,
    round(abs(f.valor), 2) as valor
  from public.fato_financeiro f
  where f.data_caixa = p_dia
    and f.movimentacao = 'Débito'
    and f.entra_dre
    and f.empresa = any(array['PRAIA', 'BB']::text[])
  order by abs(f.valor) desc, 1;
end;
$function$;

comment on function public.listar_despesas_dia(date) is
  'Despesas individuais de um dia (mesmo recorte da coluna Despesas do calendario financeiro).';

revoke all privileges on function public.listar_despesas_dia(date)
  from public, anon, authenticated;
grant execute on function public.listar_despesas_dia(date) to authenticated;

commit;
