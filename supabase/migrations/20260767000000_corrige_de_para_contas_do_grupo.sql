-- =====================================================================
-- Corrige de_para das contas do proprio grupo (eram "Recebivel de Cartao")
-- =====================================================================
--
-- PROBLEMA
--   A 20260765000000 tentou mapear as contas do proprio grupo para
--   "Transferencia entre Contas", mas o insert usava
--   "where not exists (... chave_tipo/chave_valor ...)". Tres chaves ja
--   existiam apontando para "Recebivel de Cartao" e por isso foram
--   silenciosamente ignoradas:
--
--     id 2612  SIRFISHERCOMERCIODEALIMENTOSLTDA  -> Recebivel de Cartao
--     id 2613  SIRFISHERIMPRENSA                 -> Recebivel de Cartao
--     id 2614  SIRFISHERPRAIA                    -> Recebivel de Cartao
--
--   Resultado: Pix ENVIADOS para contas da propria empresa ficaram
--   classificados como "Recebivel de Cartao" (dre_grupo RECEITAS) e,
--   por serem debitos, entram na DRE como despesa do grupo de receita.
--
--   Conferido no fato_financeiro antes desta migration -- os 14 usos
--   dessas chaves nas fontes vivas sao TODOS debitos, nenhum credito:
--     inter  10 debitos  R$ 42.000,00  (11/08/2025 a 19/11/2025)
--     bb      4 debitos  R$  1.926,95  (03/02/2026 a 08/05/2026)
--   Logo, a correcao nao altera receita de nenhum mes: apenas retira
--   R$ 43.926,95 de despesa indevida da DRE, reconhecendo-a como
--   movimentacao entre contas do grupo.
--
-- SOLUCAO
--   Update das tres chaves para "Transferencia entre Contas" (grupo
--   CONTABIL, ja excluido da DRE pela 20260748000000). O update e
--   idempotente e so toca linhas que ainda estejam em "Recebivel de
--   Cartao".
--
-- NAO ALTERADO DE PROPOSITO
--   id 2268  HEMILEALEXANDRESILVA -> Folha Salarial. A titular da conta
--   Inter tem 155 debitos no historico (R$ 147.152,40, 2021-2025) e 13
--   debitos na Stone em 2026 (R$ 28.652,83) classificados como folha.
--   Nao ha como decidir sem o usuario se sao salario ou aporte na conta
--   Inter; mudar em bloco reescreveria R$ 175 mil de PESSOAL. A chave
--   '35220527HEMILEALEXANDRESILVA' (formato usado nos Pix identificados
--   como vindos da conta Inter) ja foi mapeada para transferencia na
--   20260765000000, entao os casos confirmados estao cobertos.
--   Pendencia registrada em docs/CANAL_IA.md.
--
-- OBJETOS
--   ~ public.de_para (3 linhas de dados)
--
-- RISCO: baixo. Nenhuma view, funcao ou schema alterado. Reduz despesa
--   reportada em R$ 43.926,95 distribuidos entre ago/2025 e mai/2026,
--   corrigindo uma superestimativa. Reversivel: voltar as tres linhas
--   para 'Recebivel de Cartao'.
-- =====================================================================

begin;

update public.de_para
set categoria = 'Transferencia entre Contas',
    atualizado_em = now()
where chave_tipo = 'nome'
  and chave_valor in (
    'SIRFISHERCOMERCIODEALIMENTOSLTDA',
    'SIRFISHERIMPRENSA',
    'SIRFISHERPRAIA'
  )
  and categoria = 'Recebível de Cartão';

commit;
