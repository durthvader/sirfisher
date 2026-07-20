-- =====================================================================
-- Corrige contagem dupla no colchao de despesa fixa e expoe o calculo
-- =====================================================================
--
-- PROBLEMA
--   projecao_despesa_fixa calcula, para os dias que faltam no mes:
--     colchao = greatest(media_tipica_3_meses - "ja pago", 0) / dias_restantes
--   Mas o "ja pago" so somava conta_recorrente_pagamento (situacao='pago'),
--   enquanto a media_tipica e calculada em cima de TODO fato_financeiro dos
--   grupos PESSOAL/INFRAESTRUTURA/MARKETING E PUBLICIDADE/IMPOSTOS. Despesa
--   fixa paga por fora do controle de recorrentes (ex.: folha via BS Cash,
--   antes da 20260755000000/20260756000000) nunca abatia o colchao — o app
--   reprojetava, nos dias futuros, dinheiro que ja tinha saido do caixa.
--
--   Medido apos importar o extrato do BS Cash em dia (folha de julho completa
--   no fato_financeiro): conta_recorrente_pagamento registrava um total pago
--   bem menor que o realizado real nos mesmos 4 grupos DRE, entao o colchao
--   saia superestimado. Essa diferenca explicava quase todo o gap restante
--   contra a planilha historica do dono.
--
-- SOLUCAO
--   Trocar a fonte do "ja realizado" de conta_recorrente_pagamento para o
--   MESMO universo usado no calculo da media (fato_financeiro, mesmos grupos,
--   por competencia). Media e realizado passam a vir da mesma fonte — deixa
--   de comparar duas contagens diferentes.
--
--   Efeito colateral desejado: como a despesa fixa real (folha, impostos)
--   entra de forma mais completa e mais cedo no mes do que so os recorrentes
--   cadastrados, o colchao encolhe mais rapido e de forma mais uniforme ao
--   longo do mes — reduz a "flutuacao" que o dono via nos ultimos dias do
--   mes. Nao foi necessario mudar a forma da distribuicao (segue dividido
--   igualmente pelos dias restantes do mes): a instabilidade vinha sobretudo
--   do numerador subestimado, nao do formato da divisao.
--
--   Meses futuros (sem fato_financeiro ainda) nao mudam: "ja realizado" era
--   0 e continua 0, entao o colchao ali continua sendo a media tipica cheia,
--   igual a antes.
--
-- VISIBILIDADE (pedido do dono: "queria ter visibilidade desse colchao")
--   Nova view public.painel_colchao_despesa_fixa expoe, por mes aberto:
--   media_tipica, ja_realizado, colchao (total) e valor_dia. Segue o mesmo
--   padrao das demais painel_*: sem grant direto, pronta para um wrapper
--   app_* quando a tela que vai mostrar isso for definida (ainda nao existe
--   UI para este dado; a mudanca aqui e so o calculo + a leitura).
--
-- RISCO: baixo/medio.
--   - Muda o valor de despesa fixa projetada do(s) mes(es) aberto(s) DESTE
--     ciclo (normalmente so o mes corrente): o colchao fica menor porque
--     agora conta a despesa fixa real ja saida do caixa. Meses fechados e
--     futuros nao mudam.
--   - saldo_mensal_calculado/fluxo_caixa_diario ja somam projecao_despesa_fixa
--     por dia; o SOMATORIO do mes muda (para menos), o saldo projetado de
--     fim de mes sobe na mesma proporcao. Nenhuma tabela e alterada, so as
--     duas views.
--
-- OBJETOS
--   ~ public.projecao_despesa_fixa          (troca a fonte do "ja realizado")
--   + public.painel_colchao_despesa_fixa    (nova, visibilidade do calculo)
-- =====================================================================

begin;

create or replace view public.projecao_despesa_fixa as
with media as (
  select coalesce(avg(m.total), 0::numeric) as media_mensal
  from (
    select
      date_trunc('month', f.data_competencia) as mes,
      sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.movimentacao like 'D%'
      and f.dre_grupo = any (array[
        'PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'
      ])
      and f.data_competencia >= date_trunc('month', current_date) - interval '3 months'
      and f.data_competencia < date_trunc('month', current_date)
    group by 1
  ) m
),
-- Mesma fonte e mesmos grupos da "media" acima — antes era
-- conta_recorrente_pagamento, um subconjunto que ficava para tras quando
-- despesa fixa era paga por fora do controle de recorrentes.
realizado_mes as (
  select
    date_trunc('month', f.data_competencia) as mes,
    sum(abs(f.valor)) as realizado
  from public.fato_financeiro f
  where f.movimentacao like 'D%'
    and f.dre_grupo = any (array[
      'PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'
    ])
  group by 1
),
dias_restantes as (
  select c.mes, count(*) as n
  from public.calendario c
  where c.dia > (select cc.dia from public.corte_caixa cc)
  group by c.mes
)
select
  c.dia,
  round(
    greatest((select media_mensal from media) - coalesce(rm.realizado, 0), 0)
    / dr.n::numeric,
    2
  ) as valor
from public.calendario c
join dias_restantes dr on dr.mes = c.mes
left join realizado_mes rm on rm.mes = c.mes
where c.dia > (select cc.dia from public.corte_caixa cc);

create or replace view public.painel_colchao_despesa_fixa as
with media as (
  select coalesce(avg(m.total), 0::numeric) as media_mensal
  from (
    select
      date_trunc('month', f.data_competencia) as mes,
      sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.movimentacao like 'D%'
      and f.dre_grupo = any (array[
        'PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'
      ])
      and f.data_competencia >= date_trunc('month', current_date) - interval '3 months'
      and f.data_competencia < date_trunc('month', current_date)
    group by 1
  ) m
),
realizado_mes as (
  select
    date_trunc('month', f.data_competencia) as mes,
    sum(abs(f.valor)) as realizado
  from public.fato_financeiro f
  where f.movimentacao like 'D%'
    and f.dre_grupo = any (array[
      'PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'
    ])
  group by 1
),
dias_restantes as (
  select c.mes, count(*) as n
  from public.calendario c
  where c.dia > (select cc.dia from public.corte_caixa cc)
  group by c.mes
)
select
  dr.mes,
  round((select media_mensal from media), 2) as media_tipica,
  round(coalesce(rm.realizado, 0), 2) as ja_realizado,
  round(greatest((select media_mensal from media) - coalesce(rm.realizado, 0), 0), 2) as colchao,
  dr.n as dias_restantes,
  round(
    greatest((select media_mensal from media) - coalesce(rm.realizado, 0), 0)
    / dr.n::numeric,
    2
  ) as valor_dia
from dias_restantes dr
left join realizado_mes rm on rm.mes = dr.mes
order by dr.mes;

commit;
