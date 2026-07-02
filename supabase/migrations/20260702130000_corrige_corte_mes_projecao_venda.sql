-- =====================================================================
-- Corrige o corte de mes usado na projecao de venda diaria
-- =====================================================================
--
-- PROBLEMA
--   tendencia_mes e projecao_venda_diaria decidem qual e o "mes em
--   andamento" usando date_trunc('month', CURRENT_DATE) -- ou seja, o
--   calendario do servidor -- em vez do mes do ultimo dado de venda
--   realmente carregado (corte_venda.dia).
--
--   Efeito pratico: se uma carga atrasa e o calendario vira o mes antes
--   de voce importar os dias que faltam, o mes anterior passa a ser
--   tratado como "ja fechado" e sua projecao deixa de ser extrapolada
--   pelo ritmo das vendas -- vira uma soma simples dos dias que ja
--   existem. Os dias que ainda faltavam projetar naquele mes despencam
--   silenciosamente.
--
--   Validado com uma simulacao (somente leitura, dados reais de junho/26
--   com um corte artificial em 15/06): abrindo ainda em junho, a
--   tendencia extrapolada do mes era R$ 177.051,89 (venda projetada de
--   25/06 = R$ 4.477,17). Abrindo em julho, sem nenhuma carga nova, a
--   mesma projecao caia para R$ 91.171,55 (apenas a soma dos 15 dias
--   reais) e a venda projetada de 25/06 caia para R$ 2.305,49 -- uma
--   queda de 48% pela simples passagem do calendario, sem qualquer
--   mudanca nos dados.
--
-- SOLUCAO
--   Trocar a referencia de "mes atual" de CURRENT_DATE para o mes de
--   corte_venda.dia (max(dia) em venda_diaria = ultimo dado carregado).
--   Assim o mes em extrapolacao e sempre o mes do ultimo dado, nao o mes
--   do calendario -- o resultado passa a ser o mesmo independente de que
--   dia a pagina e aberta, so mudando quando uma nova carga entra.
--
-- OBJETOS AFETADOS (mesmas colunas/tipos de saida em ambas -- sem
-- mudanca de schema, so troca da fonte interna do "mes atual"):
--   ~ tendencia_mes
--   ~ projecao_venda_diaria
--
-- EFEITO EM CASCATA (nenhuma alteracao direta nestes; passam a receber
-- o valor corrigido automaticamente por dependerem das views acima):
--   recebimento_projetado, projecao_despesa_direta, fluxo_caixa_diario,
--   mv_fluxo_caixa_diario (snapshot do caixa.html), painel_venda_mes_atual.
--
-- RISCO: baixo.
--   - Sem mudanca de colunas/tipos -> create or replace aceito.
--   - Quando o mes ja esta 100% carregado (ex.: hoje, corte_venda cai no
--     ultimo dia do mes) o resultado matematico e identico ao de antes;
--     so muda o comportamento no cenario com carga atrasada, que e
--     exatamente o bug.
--   - Nao inclui um REFRESH do snapshot do caixa (mv_fluxo_caixa_diario)
--     aqui para nao arriscar a migration inteira por causa de restricoes
--     de REFRESH CONCURRENTLY dentro de transacao. Nao ha urgencia: hoje
--     corte_venda cai exatamente no ultimo dia do mes, entao o bug nao
--     esta ativo neste momento. O snapshot pega a correcao normalmente
--     na proxima importacao (refresh_painel()); se quiser refletir antes
--     disso, rode manualmente: select refresh_painel();
-- =====================================================================

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
      coalesce(sum(c.peso), 0::numeric) as peso_decorrido,
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
    c.peso,
    case
      when c.dia <= (select corte.dia from corte) then coalesce(v.bruto, 0::numeric)
      else round(coalesce(mt.total_esperado, 0::numeric) * c.peso / nullif(mt.peso_total, 0::numeric), 2)
    end as venda,
    case
      when c.dia <= (select corte.dia from corte) then 'real'::text
      else 'projetado'::text
    end as tipo
  from calendario c
    left join venda_diaria v on v.dia = c.dia
    left join mes_total mt on mt.mes = c.mes;
