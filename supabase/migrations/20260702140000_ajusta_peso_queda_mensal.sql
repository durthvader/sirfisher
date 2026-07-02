-- =====================================================================
-- Aplica fator de queda mensal (0,59% ao dia) ao peso usado na tendencia
-- =====================================================================
--
-- PROBLEMA
--   A tendencia/projecao de venda usa calendario.peso (peso por dia da
--   semana + feriado) para extrapolar o ritmo de vendas para o mes
--   inteiro, mas nao considera que dias no fim do mes tendem a vender
--   menos que dias no inicio do mes, mesmo tendo o mesmo peso de dia da
--   semana. A planilha Excel antiga tinha esse ajuste (queda media de
--   0,59% ao dia, apurada por analise historica) e a migracao para o
--   Supabase nao reproduziu esse fator.
--
-- SOLUCAO
--   Um unico ponto de verdade: a formula de queda entra como uma nova
--   coluna peso_ajustado na view calendario (fonte de todo peso do
--   sistema). As 5 views que fazem calculo de tendencia/projecao trocam
--   a referencia de calendario.peso para calendario.peso_ajustado.
--   calendario.peso (bruto, por dia da semana/feriado) continua existindo
--   sem nenhuma mudanca -- feriado e peso_dia_semana nao sao alterados.
--
--   Formula (dia_do_mes direto, sem subtrair 1, para replicar a
--   planilha antiga):
--     peso_ajustado = peso * power(0.9941, extract(day from dia))
--
-- OBJETOS AFETADOS
--   ~ calendario              -> + coluna peso_ajustado (apendada no
--                                 final da lista; peso bruto inalterado)
--   ~ peso_mensal             -> peso_total soma peso_ajustado
--   ~ tendencia_mes           -> peso_decorrido soma peso_ajustado
--   ~ projecao_venda_diaria   -> coluna "peso" exposta passa a ser o
--                                 valor ajustado; formula de venda usa
--                                 peso_ajustado
--   ~ painel_diario           -> meta_dia/projecao_fechamento usam
--                                 peso_ajustado (usada hoje em
--                                 index.html e vendas.html)
--   ~ painel_tendencia_diaria -> mesma troca (nao usada por nenhuma
--                                 pagina hoje, mantida consistente)
--
--   painel_venda_mes_atual NAO e alterada diretamente: ela le
--   projecao_venda_diaria.peso e peso_mensal.peso_total, que ja saem
--   corrigidos das views acima.
--
--   projecao_despesa_fixa e fluxo_caixa_diario NAO usam peso para
--   calculo (a primeira divide por quantidade de dias; a segunda so
--   seleciona calendario.peso sem usar) -- ficam de fora de proposito.
--
-- EXEMPLO (dados reais de julho/2026, corte em 01/07, vendido R$3.795,94)
--   peso_total do mes:      436        -> 397,47
--   peso_decorrido (01/07): 10         -> 9,941
--   tendencia do mes:       R$165.502,98 -> R$151.772,49
--
-- RISCO: baixo.
--   - calendario.peso_ajustado e coluna nova, apendada ao final -> nao
--     quebra CREATE OR REPLACE VIEW (que exige mesmas colunas/tipos nas
--     posicoes existentes, permitindo apenas acrescentar no final).
--   - peso (calendario), peso_total (peso_mensal/tendencia_mes),
--     peso_decorrido (tendencia_mes) e peso_acum (painel_tendencia_diaria)
--     ja sao numeric sem precisao fixa -> sem incompatibilidade de tipo.
--   - Muda o VALOR de tendencia/projecao de venda e da linha "Meta" do
--     grafico da Visao Geral (index.html) -- efeito esperado e desejado
--     desta mudanca, nao um bug colateral.
--   - Nao inclui REFRESH do snapshot do caixa (mv_fluxo_caixa_diario)
--     pelo mesmo motivo da migration anterior (evitar REFRESH
--     CONCURRENTLY dentro de transacao). O snapshot pega os novos
--     valores na proxima importacao (refresh_painel()); para aplicar
--     antes disso, rode manualmente: select refresh_painel();
-- =====================================================================

create or replace view calendario as
  select
    g.d::date as dia,
    extract(dow from g.d)::integer as dow,
    coalesce(f.peso, w.peso) as peso,
    coalesce(f.tipo, 'normal'::text) as tipo_dia,
    f.nome as evento,
    date_trunc('month'::text, g.d)::date as mes,
    to_char(g.d, 'YYYY-MM'::text) as ano_mes,
    extract(year from g.d)::integer as ano,
    round(coalesce(f.peso, w.peso) * power(0.9941::numeric, extract(day from g.d)::numeric), 6) as peso_ajustado
  from generate_series('2021-12-01'::date::timestamp with time zone, (current_date + '1 year'::interval)::date::timestamp with time zone, '1 day'::interval) g(d)
    left join feriado f on f.data = g.d::date
    left join peso_dia_semana w on w.dow = extract(dow from g.d)::integer;

create or replace view peso_mensal as
  select mes, sum(peso_ajustado) as peso_total
  from calendario
  group by mes;

create or replace view tendencia_mes as
  with mes_atual as (
    select date_trunc('month', cv.dia::timestamp with time zone)::date as mes
    from corte_venda cv
  ), ref as (
    select max(v.dia) as dia_ref
    from venda_diaria v, mes_atual m
    where date_trunc('month', v.dia::timestamp with time zone) = m.mes
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

create or replace view projecao_venda_diaria as
  with corte as (
    select corte_venda.dia
    from corte_venda
  ), mes_corte as (
    select date_trunc('month', cv.dia::timestamp with time zone)::date as mes
    from corte_venda cv
  ), mes_total as (
    select
      c.mes,
      case
        when c.mes < (select mes from mes_corte) then
          (select coalesce(sum(v1.bruto), 0::numeric)
           from venda_diaria v1
           where date_trunc('month', v1.dia::timestamp with time zone) = c.mes)
        when c.mes = (select mes from mes_corte) then
          coalesce(
            (select tendencia_mes.tendencia from tendencia_mes),
            (select m1.meta_bruta from meta_mensal m1 where m1.mes = c.mes and m1.unidade = 'PRAIA')
          )
        else
          (select m1.meta_bruta from meta_mensal m1 where m1.mes = c.mes and m1.unidade = 'PRAIA')
      end as total_esperado,
      (select p.peso_total from peso_mensal p where p.mes = c.mes) as peso_total
    from (select distinct calendario.mes from calendario) c
  )
  select
    c.dia,
    c.mes,
    c.peso_ajustado as peso,
    case
      when c.dia <= (select corte.dia from corte) then coalesce(v.bruto, 0::numeric)
      else round(coalesce(mt.total_esperado, 0::numeric) * c.peso_ajustado / nullif(mt.peso_total, 0::numeric), 2)
    end as venda,
    case
      when c.dia <= (select corte.dia from corte) then 'real'::text
      else 'projetado'::text
    end as tipo
  from calendario c
    left join venda_diaria v on v.dia = c.dia
    left join mes_total mt on mt.mes = c.mes;

create or replace view painel_diario as
  with horizonte as (
    select (current_date + ((( select parametros.valor from parametros where parametros.chave = 'horizonte_meses') || ' months')::interval))::date as fim
  ), base as (
    select c.dia, c.mes, c.peso_ajustado,
        coalesce(v.bruto, 0::numeric) as venda_calc,
        c.dia <= (select corte_venda.dia from corte_venda) as eh_real
    from calendario c
      left join venda_diaria v on v.dia = c.dia
    where c.dia <= (select horizonte.fim from horizonte)
  ), acum as (
    select b.dia, b.mes, b.peso_ajustado, b.venda_calc, b.eh_real,
        sum(case when b.eh_real then b.venda_calc else 0::numeric end) over (partition by b.mes order by b.dia) as vendido_acum,
        sum(case when b.eh_real then b.peso_ajustado else 0::numeric end) over (partition by b.mes order by b.dia) as peso_acum
    from base b
  )
  select a.dia, a.mes,
    case when a.eh_real then a.venda_calc else null::numeric end as venda_dia,
    round(mm.meta_bruta * a.peso_ajustado / nullif(pm.peso_total, 0::numeric), 2) as meta_dia,
    mm.meta_bruta as meta_mes,
    pm.peso_total,
    case when a.eh_real then round(a.vendido_acum / nullif(a.peso_acum, 0::numeric) * pm.peso_total, 2) else null::numeric end as projecao_fechamento
  from acum a
    left join peso_mensal pm on pm.mes = a.mes
    left join meta_mensal mm on mm.mes = a.mes and mm.unidade = 'PRAIA'
  order by a.dia;

create or replace view painel_tendencia_diaria as
  with dias_reais as (
    select c.dia, c.mes, c.peso_ajustado,
        coalesce(v.bruto, 0::numeric) as venda_dia
    from calendario c
      left join venda_diaria v on v.dia = c.dia
    where c.dia <= (select corte_venda.dia from corte_venda)
  ), acum as (
    select dias_reais.dia, dias_reais.mes, dias_reais.peso_ajustado, dias_reais.venda_dia,
        sum(dias_reais.venda_dia) over (partition by dias_reais.mes order by dias_reais.dia) as vendido_acum,
        sum(dias_reais.peso_ajustado) over (partition by dias_reais.mes order by dias_reais.dia) as peso_acum
    from dias_reais
  )
  select a.dia, a.mes, a.venda_dia, a.vendido_acum, a.peso_acum, pm.peso_total,
    round(a.vendido_acum / nullif(a.peso_acum, 0::numeric) * pm.peso_total, 2) as projecao_fechamento,
    mm.meta_bruta as meta
  from acum a
    left join peso_mensal pm on pm.mes = a.mes
    left join meta_mensal mm on mm.mes = a.mes and mm.unidade = 'PRAIA'
  order by a.dia;
