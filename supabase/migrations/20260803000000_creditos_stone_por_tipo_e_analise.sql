-- =====================================================================
-- Creditos Stone: Transacao e venda; PIX herdado de despesa exige analise
-- =====================================================================
--
-- PROBLEMA
--   O de_para por contraparte era aplicado antes do tipo do lancamento.
--   Assim, vendas Stone do tipo Transacao herdavam categorias usadas nos
--   pagamentos para a mesma pessoa/empresa (Folha, Diaria, Manutencao etc.).
--   A tentativa anterior de resolver apenas PIX/PESSOAL tambem ficou ampla:
--   um credito Pix pode ser venda, devolucao, transferencia ou outra entrada.
--
-- SOLUCAO
--   1. Credito Stone do tipo Transacao usa Transacao/RECEITAS antes do de_para.
--   2. Credito Stone do tipo Pix que herdaria categoria de natureza Despesa
--      fica com status analise e aparece em Analise individual.
--   3. Transferencia propria, ANALISAR INDIVIDUAL explicito e ajuste manual
--      continuam prevalecendo.
--
-- IMPLEMENTACAO
--   A view e grande e sua definicao canonica vem da migration imediatamente
--   anterior. Alteramos somente tres trechos conhecidos, abortando se algum
--   deles nao existir exatamente uma vez. A guarda torna a migration
--   reexecutavel depois que a nova regra ja estiver instalada.
--
-- OBJETO
--   ~ public.fato_financeiro (mesmas colunas e tipos)
-- =====================================================================

begin;

do $migration$
declare
  v_def text;
  v_old_match constant text := $oldmatch$cdp.dre_grupo AS dp_grupo$oldmatch$;
  v_new_match constant text := $newmatch$cdp.dre_grupo AS dp_grupo,
            cdp.natureza AS dp_natureza$newmatch$;
  v_old_cat constant text := $oldcat$WHEN lm.dp_cat = 'ANALISAR INDIVIDUAL'::text THEN NULL::text
                    WHEN lm.origem = 'stone_extrato'::text AND lm.movimentacao = 'Crédito'::text AND lm.tipo = 'Pix'::text AND lm.dp_grupo = 'PESSOAL'::text THEN 'PIX'::text
                    WHEN lm.dp_cat IS NOT NULL THEN lm.dp_cat$oldcat$;
  v_new_cat constant text := $newcat$WHEN lm.dp_cat = 'ANALISAR INDIVIDUAL'::text THEN NULL::text
                    WHEN lm.origem = 'stone_extrato'::text AND lm.movimentacao = 'Crédito'::text AND lm.tipo = 'Transação'::text THEN 'Transação'::text
                    WHEN lm.origem = 'stone_extrato'::text AND lm.movimentacao = 'Crédito'::text AND lm.tipo = 'Pix'::text AND lm.dp_natureza = 'Despesa'::text THEN NULL::text
                    WHEN lm.dp_cat IS NOT NULL THEN lm.dp_cat$newcat$;
  v_old_status constant text := $oldstatus$WHEN lm.dp_cat = 'ANALISAR INDIVIDUAL'::text THEN 'analise'::text
                    WHEN lm.origem = 'stone_extrato'::text AND lm.movimentacao = 'Crédito'::text AND lm.tipo = 'Pix'::text AND lm.dp_grupo = 'PESSOAL'::text THEN 'classificado'::text
                    WHEN lm.dp_cat IS NOT NULL THEN 'classificado'::text$oldstatus$;
  v_new_status constant text := $newstatus$WHEN lm.dp_cat = 'ANALISAR INDIVIDUAL'::text THEN 'analise'::text
                    WHEN lm.origem = 'stone_extrato'::text AND lm.movimentacao = 'Crédito'::text AND lm.tipo = 'Transação'::text THEN 'classificado'::text
                    WHEN lm.origem = 'stone_extrato'::text AND lm.movimentacao = 'Crédito'::text AND lm.tipo = 'Pix'::text AND lm.dp_natureza = 'Despesa'::text THEN 'analise'::text
                    WHEN lm.dp_cat IS NOT NULL THEN 'classificado'::text$newstatus$;
begin
  v_def := pg_get_viewdef('public.fato_financeiro'::regclass, true);

  if position('cdp.natureza AS dp_natureza' in v_def) > 0
     and position($marker$lm.tipo = 'Transação'::text THEN 'Transação'::text$marker$ in v_def) > 0
     and position($marker$lm.dp_natureza = 'Despesa'::text THEN 'analise'::text$marker$ in v_def) > 0 then
    return;
  end if;

  if (length(v_def) - length(replace(v_def, v_old_match, ''))) <> length(v_old_match) then
    raise exception 'Trecho live_match esperado nao foi encontrado exatamente uma vez.';
  end if;
  if (length(v_def) - length(replace(v_def, v_old_cat, ''))) <> length(v_old_cat) then
    raise exception 'Trecho cat_final esperado nao foi encontrado exatamente uma vez.';
  end if;
  if (length(v_def) - length(replace(v_def, v_old_status, ''))) <> length(v_old_status) then
    raise exception 'Trecho status_final esperado nao foi encontrado exatamente uma vez.';
  end if;

  v_def := replace(v_def, v_old_match, v_new_match);
  v_def := replace(v_def, v_old_cat, v_new_cat);
  v_def := replace(v_def, v_old_status, v_new_status);

  execute 'create or replace view public.fato_financeiro as ' || v_def;
end;
$migration$;

comment on view public.fato_financeiro is
  'Fato financeiro unificado; credito Stone Transacao e receita, enquanto Pix que herdaria categoria de despesa exige analise individual. Transferencias proprias e ajustes manuais prevalecem.';

commit;
