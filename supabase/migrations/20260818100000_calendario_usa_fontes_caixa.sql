-- Corrige o Calendario apos a consolidacao em unidade unica.
--
-- fato_financeiro.empresa passou a representar a conta bancaria, portanto os
-- filtros legados empresa in ('PRAIA', 'BB') deixaram de selecionar as saidas.
-- As duas RPCs passam a aplicar a mesma regra parametrizada de
-- caixa_real_diario: fontes conhecidas obedecem ativa + entra_caixa; linhas
-- historicas sem fonte cadastrada usam o vinculo historico configurado.
--
-- A migration troca somente o predicado dentro das funcoes existentes. Nao
-- altera dados, assinaturas, colunas retornadas, grants ou regras de saldo.

begin;

do $migration$
declare
  v_funcao regprocedure;
  v_definicao text;
  v_filtro_antigo text := $old$and f.empresa = any(array['PRAIA', 'BB']::text[])
      and f.origem is distinct from 'bs_cash'$old$;
  v_filtro_novo text := $new$and (
        exists (
          select 1
          from public.fonte_financeira cfg_fonte
          where cfg_fonte.chave = f.origem
            and cfg_fonte.ativa
            and cfg_fonte.entra_caixa
        )
        or (
          not exists (
            select 1
            from public.fonte_financeira cfg_conhecida
            where cfg_conhecida.chave = f.origem
          )
          and (
            upper(coalesce(f.empresa, '')) = upper(public.unidade_principal_nome())
            or exists (
              select 1
              from public.fonte_financeira cfg_historica
              left join public.conta conta_historica
                on conta_historica.id = cfg_historica.conta_id
              where cfg_historica.ativa
                and cfg_historica.entra_caixa
                and cfg_historica.entra_caixa_historico
                and regexp_replace(
                      lower(coalesce(f.empresa, '')),
                      '[^a-z0-9]+', '', 'g'
                    ) = any (array[
                      regexp_replace(lower(cfg_historica.chave), '[^a-z0-9]+', '', 'g'),
                      regexp_replace(lower(cfg_historica.nome), '[^a-z0-9]+', '', 'g'),
                      regexp_replace(lower(coalesce(conta_historica.nome, '')), '[^a-z0-9]+', '', 'g'),
                      regexp_replace(lower(coalesce(conta_historica.banco, '')), '[^a-z0-9]+', '', 'g')
                    ])
            )
          )
        )
      )$new$;
  v_ocorrencias integer;
  v_esperadas integer;
begin
  for v_funcao, v_esperadas in
    select 'public.listar_calendario_financeiro(date)'::regprocedure, 2
    union all
    select 'public.listar_despesas_dia(date)'::regprocedure, 1
  loop
    select pg_get_functiondef(v_funcao) into v_definicao;

    v_ocorrencias := (
      length(v_definicao) - length(replace(v_definicao, v_filtro_antigo, ''))
    ) / length(v_filtro_antigo);

    if v_ocorrencias = 0
       and position('cfg_fonte.entra_caixa' in v_definicao) > 0 then
      continue;
    end if;

    if v_ocorrencias <> v_esperadas then
      raise exception
        'Predicado legado inesperado em %: esperado %, encontrado %.',
        v_funcao, v_esperadas, v_ocorrencias;
    end if;

    execute replace(v_definicao, v_filtro_antigo, v_filtro_novo);
  end loop;
end;
$migration$;

do $validacao$
declare
  v_def_calendario text := pg_get_functiondef(
    'public.listar_calendario_financeiro(date)'::regprocedure
  );
  v_def_detalhe text := pg_get_functiondef(
    'public.listar_despesas_dia(date)'::regprocedure
  );
begin
  if position($old$and f.empresa = any(array['PRAIA', 'BB']::text[])$old$
              in v_def_calendario) > 0
     or position($old$and f.empresa = any(array['PRAIA', 'BB']::text[])$old$
                 in v_def_detalhe) > 0 then
    raise exception 'O filtro legado de empresa permaneceu nas RPCs do Calendario.';
  end if;

  if position($old$and f.origem is distinct from 'bs_cash'$old$
              in v_def_calendario) > 0
     or position($old$and f.origem is distinct from 'bs_cash'$old$
                 in v_def_detalhe) > 0 then
    raise exception 'A exclusao fixa de BS Cash permaneceu nas RPCs do Calendario.';
  end if;

  if position('cfg_fonte.entra_caixa' in v_def_calendario) = 0
     or position('cfg_fonte.entra_caixa' in v_def_detalhe) = 0 then
    raise exception 'A regra parametrizada de fontes nao foi instalada nas RPCs do Calendario.';
  end if;
end;
$validacao$;

comment on function public.listar_calendario_financeiro(date) is
  'Calendario financeiro da unidade unica; realizado respeita as fontes configuradas para entrar no caixa e a projecao permanece encadeada entre meses.';

comment on function public.listar_despesas_dia(date) is
  'Saidas das fontes configuradas para entrar no caixa e baixa do dinheiro pendente; detalhamento diario do Calendario.';

commit;
