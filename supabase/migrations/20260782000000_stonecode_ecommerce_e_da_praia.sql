-- =====================================================================
-- O stonecode 173835323 (E-commerce) e da PRAIA
-- =====================================================================
--
-- CONTEXTO
--   A 20260781000000 cadastrou os tres estabelecimentos que o usuario
--   identificou (Praia, Imprensa, PUB) e deixou de fora o 173835323, que
--   tinha 1 venda de R$ 1.500,00 em 30/12/2025 com captura "E-commerce".
--   Como a unidade dele nao estava confirmada, ele **nao** foi excluido do
--   faturamento nem apagado -- apagar receita possivelmente real por
--   suposicao seria o erro mais caro.
--
-- EVIDENCIA
--   O relatorio da Stone e por estabelecimento. O 173835323 aparece
--   **dentro dos arquivos exportados da Praia**: no relatorio de vendas de
--   dez/2025 (1 linha entre 1.641 do 770398216) e no de recebiveis de
--   jan/2026 (1 linha entre 1.660). Se fosse de outra casa, nao viria no
--   arquivo da Praia.
--
--   E, portanto, um segundo codigo do mesmo estabelecimento -- link de
--   pagamento / e-commerce, coerente com o meio de captura e com a venda
--   parcelada em 3x, que nao existe na maquininha do balcao.
--
-- SOLUCAO
--   ~ registra 173835323 como PRAIA. Nada muda no faturamento: como o
--     filtro exclui apenas o que se sabe ser de outra unidade, essa venda
--     ja contava. O registro serve para documentar e para o importador
--     parar de avisar sobre ela em todo arquivo da Praia.
--
-- OBJETOS
--   ~ public.stone_estabelecimento (1 linha)
--
-- RISCO: nenhum. Nao altera view, nao altera valor.
-- =====================================================================

insert into public.stone_estabelecimento (stonecode, unidade, descricao) values
  ('173835323', 'PRAIA', 'Sir Fisher Praia -- e-commerce / link de pagamento')
on conflict (stonecode) do update
  set unidade = excluded.unidade,
      descricao = excluded.descricao;
