-- =====================================================================
-- Indice para os cortes por empresa no fato_financeiro
-- =====================================================================
--
-- PROBLEMA
--   A 20260765000000 introduziu dois cortes no fato_financeiro:
--     raw_bb    ... where b.data > (select max(h.data_hora)::date
--                                     from raw_historico h where h.empresa = 'BB')
--     raw_inter ... where i.data > (select max(h.data_hora)::date
--                                     from raw_historico h where h.empresa = 'Inter')
--
--   Sem indice, cada um vira Seq Scan em raw_historico (47.601 linhas,
--   cost 3.314) -- confirmado no explain. fato_financeiro nao e
--   materializada e saldo_mensal_calculado a alcanca por varios caminhos
--   (a 20260752000000 ja media 29 seq scans por recalculo), entao esses
--   dois subselects sao reavaliados dezenas de vezes numa unica chamada
--   de recalcular_saldo_fechamento.
--
--   Efeito observado em producao (25/07/2026, ~00:25-00:33 UTC): o job
--   'sirfisher-processar-recalculo-saldo' consumiu memoria suficiente
--   para derrubar a instancia; o Postgres reiniciou, o item da fila
--   continuou pendente e o cron reprocessou a cada 5s, formando um
--   crashloop (6 execucoes seguidas com "server restarted", logs com
--   "the database system is starting up"). O job foi desagendado e o
--   item 13 da fila marcado como erro para interromper o ciclo.
--
-- SOLUCAO
--   Indice btree (empresa, data_hora desc) em raw_historico. Os dois
--   subselects passam a resolver por index scan (primeira linha do
--   grupo) em vez de varrer a tabela inteira. Sem mudanca de semantica:
--   mesmas linhas, mesmo resultado.
--
--   O indice tambem serve o filtro por empresa usado no braco historico
--   e nas consultas de conferencia por empresa.
--
-- OBJETOS
--   + index public.raw_historico_empresa_data_idx
--
-- RISCO: baixo. Indice aditivo, idempotente, sem alteracao de view,
--   regra financeira ou dado. raw_historico tem ~47 mil linhas e recebe
--   apenas carga manual, entao o lock de escrita da criacao e curto.
-- =====================================================================

begin;

create index if not exists raw_historico_empresa_data_idx
  on public.raw_historico (empresa, data_hora desc);

comment on index public.raw_historico_empresa_data_idx is
  'Resolve os cortes por empresa do fato_financeiro (max(data_hora) por empresa) sem seq scan.';

commit;

analyze public.raw_historico;
