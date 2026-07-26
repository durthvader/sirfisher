-- =====================================================================
-- Chave unica dos recebiveis Stone passa a incluir a categoria
-- =====================================================================
--
-- PROBLEMA
--   A restricao `uq_receb_stoneid_parcela` era `(stone_id, n_parcela)`.
--   Mas o relatorio da Stone emite **duas linhas com essa mesma chave**
--   quando a venda e cancelada:
--
--     STONE ID          Nº PARCELA   CATEGORIA
--     15962591134455    1            Venda
--     15962591134455    1            Cancelamento
--
--   Com `on conflict (stone_id, n_parcela) do nothing`, so a **primeira**
--   linha do arquivo sobrevive -- e qual delas e depende da ordem em que a
--   Stone gerou o CSV. Nao ha criterio nenhum: e sorte.
--
--   Impacto financeiro real: `venda_diaria` desconta da venda Stone o
--   `sum(abs(valor_bruto))` das linhas de cancelamento. Quando a linha que
--   sobrevive e a de `Venda`, o cancelamento **nao existe no banco** e nao
--   e descontado -- o faturamento fica superestimado.
--
--   Medido: a base tinha 4 cancelamentos registrados quando deveria ter 7.
--   Os 3 perdidos somam R$ 149,50, dos quais R$ 114,20 caem de dez/2025 em
--   diante (o restante e um "Cancelamento Parcial" de nov/2025).
--
-- SOLUCAO
--   ~ a restricao passa a ser `(stone_id, n_parcela, categoria)`, entao a
--     linha da venda e a do cancelamento convivem, como no arquivo.
--
--   `categoria` nunca e nula nesta tabela (conferido: 0 nulos), entao nao
--   ha o risco classico de UNIQUE com NULL permitindo duplicata silenciosa.
--
--   A restricao nova **nao conflita com os dados existentes**: como eles ja
--   estavam deduplicados por (stone_id, n_parcela), qualquer trinca com a
--   categoria e automaticamente unica. Verificado em transacao revertida.
--
-- DEPOIS DESTA MIGRATION
--   Reimportar os recebiveis do periodo faz as linhas que faltavam
--   entrarem, porque agora elas sao chave nova. O
--   `03_importar_recebiveis_stone.py` foi ajustado no mesmo commit para
--   usar o conflito de tres colunas.
--
-- LIMITACAO CONHECIDA
--   Cancelamentos anteriores ao periodo reimportado seguem perdidos -- a
--   linha foi descartada na carga original e nao ha como recuperar sem o
--   arquivo. Para recuperar, reexportar o periodo e reimportar.
--
-- OBJETOS
--   ~ public.raw_stone_recebiveis (restricao unica)
--
-- RISCO: baixo. Troca de restricao, sem alterar dado. A restricao antiga
--   era mais estrita, entao nada que ja esta gravado passa a violar nada.
-- =====================================================================

alter table public.raw_stone_recebiveis
  drop constraint if exists uq_receb_stoneid_parcela;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'uq_receb_stoneid_parcela_categoria'
      and conrelid = 'public.raw_stone_recebiveis'::regclass
  ) then
    alter table public.raw_stone_recebiveis
      add constraint uq_receb_stoneid_parcela_categoria
      unique (stone_id, n_parcela, categoria);
  end if;
end $$;

comment on constraint uq_receb_stoneid_parcela_categoria
  on public.raw_stone_recebiveis is
  'A Stone emite Venda e Cancelamento com o mesmo STONE ID e numero de parcela; a categoria faz parte da identidade da linha. Sem ela, o cancelamento era descartado na carga e deixava de ser abatido do faturamento.';
