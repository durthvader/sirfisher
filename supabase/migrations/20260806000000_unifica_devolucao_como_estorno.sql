-- =====================================================================
-- Unifica "pagamento devolvido" na categoria canonica "estornado"
-- =====================================================================
--
-- As duas categorias tinham o mesmo tratamento: grupo CONTABIL, fora da DRE
-- e expectativa de saldo zero. A distincao de nome nao gerava acao diferente
-- no portal e foi removida por decisao de negocio.
--
-- A migration:
--   1. converte classificacoes persistidas para "estornado";
--   2. troca a regra automatica dos Pix devolvidos do BB;
--   3. remove a opcao redundante do cadastro de categorias;
--   4. atualiza a MV da rotina contabil imediatamente.
-- =====================================================================

begin;

update public.ajuste_manual
set categoria = 'estornado'
where categoria = 'pagamento devolvido';

update public.de_para
set categoria = 'estornado',
    atualizado_em = now()
where categoria = 'pagamento devolvido';

update public.raw_historico
set categoria = 'estornado',
    dre_grupo = 'CONTABIL'
where categoria = 'pagamento devolvido';

do $migration$
declare
  v_def text;
  v_old constant text := $old$'pagamento devolvido'::text$old$;
  v_new constant text := $new$'estornado'::text$new$;
begin
  v_def := pg_get_viewdef('public.fato_financeiro'::regclass, true);

  if position(v_old in v_def) = 0 then
    if position($marker$'Pix-Envio devolvido'::text$marker$ in v_def) > 0
       and position($marker$THEN 'estornado'::text$marker$ in v_def) > 0 then
      return;
    end if;

    raise exception 'Regra automatica de pagamento devolvido nao encontrada em fato_financeiro.';
  end if;

  if (length(v_def) - length(replace(v_def, v_old, ''))) <> length(v_old) then
    raise exception 'A categoria pagamento devolvido apareceu mais de uma vez em fato_financeiro.';
  end if;

  v_def := replace(v_def, v_old, v_new);
  execute 'create or replace view public.fato_financeiro as ' || v_def;
end;
$migration$;

delete from public.categoria_dre
where categoria = 'pagamento devolvido';

refresh materialized view public.mv_conciliacao_contabil;

comment on view public.fato_financeiro is
  'Fato financeiro unificado; estornado e a categoria canonica para estornos, cancelamentos e pagamentos devolvidos, todos fora da DRE.';

commit;
