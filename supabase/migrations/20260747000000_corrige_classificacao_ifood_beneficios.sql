-- =====================================================================
-- Corrige classificacao de repasses do vale-alimentacao (iFood Beneficios)
-- =====================================================================
--
-- PROBLEMA
--   O CNPJ 19.468.242/0001-32 pertence a Zoop Tecnologia & Instituicao de
--   Pagamento S.A., a instituicao por tras do iFood Pago/iFood Beneficios
--   (por isso o nome aparece ora como "Zoop", ora como "Ifood Pago" no
--   extrato). Sao os debitos Pix do pagamento de vale-alimentacao dos
--   funcionarios -- confirmado pelo Rogerio.
--
--   Uma parte desses lancamentos (nao todos) ficou classificada como
--   fornecedor "BDL DISTRIBUIDORA XAROPE" / categoria "Bebidas" /
--   DESPESA DIRETA DE VENDA, por engano. A maioria dos lancamentos do
--   mesmo CNPJ ja estava correta (fornecedor "IFOOD BENEFICIOS",
--   categoria "Alimentacao", grupo PESSOAL) -- e esse o padrao usado
--   aqui para os que estavam errados.
--
--   Dois pontos de origem do erro:
--   1. de_para id 1410 (chave cnpj 19468242000132): regra ativa que
--      classifica automaticamente qualquer lancamento vivo (Stone) desse
--      CNPJ como BDL/Bebidas. Afeta 13 lancamentos de jan-jul/2026 (view
--      fato_financeiro, corrigido retroativamente so de ajustar a regra).
--   2. raw_historico: 52 linhas de fev/2023 a fev/2026 tem fornecedor e
--      categoria gravados diretamente na linha (nao usam de_para).
--      Precisam de UPDATE proprio.
--
--   Conferido: nao ha ajuste_manual sobre nenhuma dessas linhas (nada
--   sobrepoe o valor corrigido).
--
-- SOLUCAO
--   1. Atualiza de_para id 1410 para fornecedor "IFOOD BENEFICIOS" /
--      categoria "Alimentacao".
--   2. Atualiza as linhas de raw_historico com fornecedor atual "BDL
--      DISTRIBUIDORA XAROPE" e destino_documento do CNPJ da Zoop para
--      fornecedor "IFOOD BENEFICIOS" / categoria "Alimentacao" / grupo
--      PESSOAL (mesmo padrao das linhas ja corretas do mesmo CNPJ).
--
-- OBJETOS AFETADOS: dados (de_para id 1410; ~52 linhas de raw_historico).
--   Nao altera nenhuma view, function ou schema.
--
-- RISCO: baixo, mas nao reversivel automaticamente (guarda os valores
--   antigos nos comentarios acima para rollback manual se necessario).
--   Idempotente: os WHERE ja excluem linhas que tenham sido corrigidas.
-- =====================================================================

begin;

update public.de_para
   set fornecedor = 'IFOOD BENEFÍCIOS',
       categoria = 'Alimentação',
       atualizado_em = now()
 where chave_tipo = 'cnpj'
   and chave_valor = '19468242000132'
   and fornecedor = 'BDL DISTRIBUIDORA XAROPE';

update public.raw_historico
   set fornecedor = 'IFOOD BENEFÍCIOS',
       categoria = 'Alimentação',
       dre_grupo = 'PESSOAL'
 where fornecedor = 'BDL DISTRIBUIDORA XAROPE'
   and destino_documento = '19.468.242/0001-32';

commit;
