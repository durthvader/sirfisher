-- Corrige linhas de raw_historico cuja categoria não corresponde a nenhuma
-- categoria válida em categoria_dre (erro de fórmula do Excel original,
-- ex.: "#N/A", ou nomes sem correspondência exata).
--
-- Levantado por consulta manual (2026-07-05):
--   '#N/A'               -> 334 linhas, soma -228.092,12
--   'Valor Desbloqueado' ->   2 linhas, soma       84,61
--   'cartão de crédito'  ->   1 linha,  soma   -7.566,79
--
-- Ao zerar categoria/dre_grupo, a view public.fato_financeiro passa a marcar
-- essas linhas com status = 'excecao' (em vez de 'classificado' com uma
-- categoria inexistente), fazendo com que apareçam em classificar_excecoes.html
-- para reclassificação manual pelo fluxo normal de DE-Para.
--
-- Nenhuma linha é apagada; apenas categoria/dre_grupo/fornecedor são zerados
-- quando inválidos. Risco: até a reclassificação manual, essas linhas ficam
-- sem dre_grupo definido (hoje já estavam com um valor incorreto).

update public.raw_historico rh
set categoria = null,
    dre_grupo = null
where rh.categoria is not null
  and not exists (
    select 1 from public.categoria_dre cd where cd.categoria = rh.categoria
  );

update public.raw_historico
set fornecedor = null
where fornecedor = '#N/A';
