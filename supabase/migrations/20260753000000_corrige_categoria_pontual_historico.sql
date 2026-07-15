-- =====================================================================
-- Corrige categoria de um lancamento pontual do Historico
-- =====================================================================
--
-- PROBLEMA
--   Um registro de raw_historico estava com categoria/dre_grupo nulos e
--   por isso aparecia sempre como pendencia em classificar_excecoes.html.
--
--   A regra "Analisar Individualmente" ja cadastrada em de_para para o
--   fornecedor envolvido nao resolve essa linha porque fato_financeiro
--   nao consulta de_para para origem = 'historico' (ver 20260730/
--   20260731/20260732). A regra continua valendo normalmente para
--   transacoes futuras desse fornecedor via Stone/BB (origem ao vivo).
--
-- ACAO
--   UPDATE pontual, restrito a essa linha (por id), classificando como
--   pagamento de fatura de cartao (Cartao BTG / CARTAO DE CREDITO),
--   confirmado com o usuario.
--
-- RISCO: baixo. Filtro por id + categoria is null torna o UPDATE
-- idempotente (nao repete efeito se a migration rodar de novo). Nao
-- altera de_para. Como dre_grupo = 'CARTAO DE CREDITO' e origem =
-- 'historico', a linha fica fora do DRE, mesmo comportamento ja aplicado
-- a outras linhas de Cartao BTG do Historico (20260738000000).
-- =====================================================================

update public.raw_historico
set categoria = 'Cartão BTG',
    dre_grupo = 'CARTÃO DE CRÉDITO'
where id = 32064
  and categoria is null;
