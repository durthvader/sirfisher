-- A unidade exposta pelo fato financeiro passa a ser sempre a unidade unica.
-- A regra entra_dre incorpora o cadastro da fonte sem remover linhas do fato.

begin;

drop table if exists pg_temp.p2_antes_fato_financeiro;
create temporary table p2_antes_fato_financeiro on commit drop as
select to_jsonb(f) - 'empresa' - 'unidade' as linha
from public.fato_financeiro f;

do $migration$
declare
  v_def text;
begin
  select pg_get_viewdef('public.fato_financeiro'::regclass, true) into v_def;
  -- pg_get_viewdef inclui um ponto e virgula final neste projeto. Dentro da
  -- subconsulta dinamica ele seria sintaxe invalida: from (<definicao>;).
  v_def := regexp_replace(v_def, ';[[:space:]]*$', '');
  if position('fonte_financeira' in v_def) > 0
     and position('unidade_principal_nome' in v_def) > 0 then
    return;
  end if;

  execute 'create or replace view public.fato_financeiro as
    select
      b.origem,
      b.raw_id,
      coalesce(c.nome, b.empresa) as empresa,
      b.data_caixa,
      b.data_competencia,
      b.movimentacao,
      b.tipo,
      b.valor,
      b.contraparte_nome,
      b.contraparte_doc,
      b.fornecedor,
      b.categoria,
      b.dre_grupo,
      b.status,
      public.unidade_principal_nome() as unidade,
      b.natureza,
      (b.entra_dre and coalesce(f.ativa and f.entra_dre, true)) as entra_dre
    from (' || v_def || ') b
    left join public.fonte_financeira f on f.chave = b.origem
    left join public.conta c on c.id = f.conta_id';
end;
$migration$;

do $validacao$
begin
  if exists (
    (select linha from pg_temp.p2_antes_fato_financeiro
     except all
     select to_jsonb(f) - 'empresa' - 'unidade' from public.fato_financeiro f)
    union all
    (select to_jsonb(f) - 'empresa' - 'unidade' from public.fato_financeiro f
     except all
     select linha from pg_temp.p2_antes_fato_financeiro)
  ) then
    raise exception 'Regressao numerica ou classificatoria em fato_financeiro.';
  end if;
end;
$validacao$;

comment on view public.fato_financeiro is
  'Fato financeiro unificado da unidade principal; participacao na DRE respeita a regra da linha e a configuracao da fonte.';

commit;
