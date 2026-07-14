-- =====================================================================
-- Corte de dados passa a considerar apenas dias completos
-- =====================================================================
--
-- PROBLEMA (dois cenarios relatados pelo usuario)
--   1. Venda em especie lancada a frente da base de cartao: corte_venda
--      e max(dia) de venda_diaria, que une Stone + especie. Lancar a
--      sangria do dia 14 com a Stone carregada so ate o dia 10 adianta
--      o corte para 14; os dias 11-14 entram na tendencia como "reais"
--      valendo so a especie (ou zero), derrubando a projecao.
--   2. Importacao no meio do dia: a base Stone importada as 15h traz o
--      dia corrente pela metade; max(dia) vira hoje e o meio-dia de
--      vendas entra na tendencia como dia completo.
--   Alem do corte, tendencia_mes tinha um vazamento proprio: o dia_ref
--   vinha de max(venda_diaria.dia) dentro do mes do corte, entao a
--   especie adiantada no mesmo mes furava o corte mesmo com a view
--   corte_venda corrigida.
--
-- SOLUCAO
--   corte_venda = least(
--     max(data_venda) da Stone,     -- fronteira da base de cartao
--     max(data) da venda_especie,   -- fronteira do lancamento manual
--     ontem em America/Sao_Paulo    -- dia em andamento nunca esta completo
--   )
--   Um dia so entra na tendencia quando TODAS as fontes ja passaram por
--   ele e o dia terminou. Semantica da especie combinada com o usuario:
--   - dia sem lancamento mas com lancamento posterior = especie zero
--     implicita (segue e conta o dia);
--   - dia sem lancamento na fronteira (nada depois) = dia fica fora da
--     tendencia ate o proximo lancamento;
--   - lancamento explicito de R$ 0 avanca a fronteira e fecha o dia.
--   Obs.: least() do Postgres ignora nulls, entao fonte vazia nao anula
--   o corte.
--
--   corte_caixa recebe apenas a trava de "ontem" (as fontes do caixa
--   sao todas importadas em lote; o problema real era o meio do dia).
--
--   tendencia_mes: dia_ref passa a vir direto de corte_venda. Hoje isso
--   e matematicamente identico (max do mes do corte == corte), so
--   elimina o vazamento da especie adiantada. Definicao replicada da
--   versao atual do banco (usa peso_ajustado, de 20260702140000).
--
-- VALIDACAO (somente leitura, dados reais de 14/07/2026):
--   o cenario estava ativo no momento da correcao: o corte apontava para
--   o proprio dia 14 (dia em andamento, base Stone parcial) e o corte
--   novo segura em 13/07. A tendencia do mes recalculada com o corte
--   novo sobe alguns por cento -- o meio-dia parcial do dia 14 estava
--   derrubando a projecao. O SELECT completo da nova tendencia_mes foi
--   validado contra o banco antes do push (mesmas colunas e tipos).
--
-- OBJETOS AFETADOS (create or replace, mesmas colunas/tipos de saida):
--   ~ corte_venda
--   ~ corte_caixa
--   ~ tendencia_mes
--
-- EFEITO EM CASCATA (sem alteracao direta; herdam o corte novo):
--   projecao_venda_diaria, painel_diario, painel_tendencia_diaria,
--   painel_venda_mes_atual, painel_resumo_mensal, recebimento_projetado,
--   projecao_despesa_direta, projecao_despesa_fixa, fluxo_caixa_diario,
--   listar_calendario_financeiro e o snapshot mv_fluxo_caixa_diario.
--
-- RISCO: baixo.
--   - Sem mudanca de colunas/tipos -> create or replace aceito e grants
--     preservados.
--   - Nao inclui REFRESH do snapshot (mv_fluxo_caixa_diario) para nao
--     arriscar a migration por restricao de REFRESH CONCURRENTLY em
--     transacao; o snapshot pega a correcao na proxima importacao
--     (refresh_painel()) ou manualmente com: select refresh_painel();
-- =====================================================================

create or replace view corte_venda as
  select least(
    (select max(v.data_venda)::date from raw_stone_vendas v),
    (select max(e.data) from venda_especie e),
    (now() at time zone 'America/Sao_Paulo')::date - 1
  ) as dia;

create or replace view corte_caixa as
  select least(
    (select max(f.data_caixa) from fato_financeiro f),
    (now() at time zone 'America/Sao_Paulo')::date - 1
  ) as dia;

create or replace view tendencia_mes as
  with mes_atual as (
    select date_trunc('month', cv.dia::timestamp with time zone)::date as mes
    from corte_venda cv
  ), ref as (
    select cv.dia as dia_ref
    from corte_venda cv
  ), decorrido as (
    select
      coalesce(sum(c.peso_ajustado), 0::numeric) as peso_decorrido,
      coalesce(sum(v.bruto), 0::numeric) as vendido
    from calendario c
      left join venda_diaria v on v.dia = c.dia
      cross join mes_atual m
      cross join ref r
    where c.mes = m.mes and r.dia_ref is not null and c.dia <= r.dia_ref
  )
  select
    m.mes,
    meta.meta_bruta as meta,
    d.vendido,
    d.peso_decorrido,
    pm.peso_total,
    r.dia_ref,
    case
      when d.peso_decorrido > 0::numeric then round(d.vendido / d.peso_decorrido * pm.peso_total, 2)
      else null::numeric
    end as tendencia,
    case
      when pm.peso_total > 0::numeric and meta.meta_bruta is not null then round(meta.meta_bruta / pm.peso_total, 2)
      else null::numeric
    end as meta_por_ponto_peso
  from mes_atual m
    cross join ref r
    cross join decorrido d
    left join peso_mensal pm on pm.mes = m.mes
    left join meta_mensal meta on meta.mes = m.mes and meta.unidade = 'PRAIA';
