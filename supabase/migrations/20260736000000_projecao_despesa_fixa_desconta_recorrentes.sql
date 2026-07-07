-- projecao_despesa_fixa: desconta das projeções o que já foi pago no mês
-- em contas recorrentes (contas_recorrentes.html).
--
-- Regra anterior: média mensal dos 3 meses fechados (débitos dos grupos DRE
-- PESSOAL, INFRAESTRUTURA, MARKETING E PUBLICIDADE e IMPOSTOS) diluída por
-- todos os dias do mês.
--
-- Regra nova: da mesma média mensal subtrai-se o total já pago na competência
-- do mês projetado (conta_recorrente_pagamento com situacao='pago', contas
-- tipo='despesa' e incluir_totais — mesmo filtro de app_contas_recorrentes_totais);
-- o restante (nunca negativo) é distribuído pelos dias ainda não realizados do
-- mês (dias após o corte de caixa). Em meses futuros sem pagamento lançado a
-- projeção continua sendo a média cheia.
--
-- Obs.: o filtro de débito usa `movimentacao like 'D%'` (só existem os valores
-- Débito/Crédito) porque o texto armazenado tem encoding corrompido ("DÃ©bito")
-- e um literal acentuado correto não casaria com os dados atuais.

begin;

create or replace view public.projecao_despesa_fixa as
with media as (
  select coalesce(avg(m.total), 0::numeric) as media_mensal
  from (
    select
      date_trunc('month', f.data_competencia::timestamp with time zone) as mes,
      sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.movimentacao like 'D%'
      and f.dre_grupo = any (array[
        'PESSOAL'::text,
        'INFRAESTRUTURA'::text,
        'MARKETING E PUBLICIDADE'::text,
        'IMPOSTOS'::text
      ])
      and f.data_competencia >= (date_trunc('month', current_date::timestamp with time zone) - interval '3 months')
      and f.data_competencia < date_trunc('month', current_date::timestamp with time zone)
    group by 1
  ) m
),
pago_recorrente as (
  select p.competencia, sum(p.valor) as pago
  from public.conta_recorrente_pagamento p
  join public.conta_recorrente c on c.id = p.conta_id
  where p.situacao = 'pago'
    and c.tipo = 'despesa'
    and c.incluir_totais
  group by p.competencia
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
    greatest((select media.media_mensal from media) - coalesce(pr.pago, 0::numeric), 0::numeric)
    / dr.n::numeric,
    2
  ) as valor
from public.calendario c
join dias_restantes dr on dr.mes = c.mes
left join pago_recorrente pr on pr.competencia = c.mes
where c.dia > (select cc.dia from public.corte_caixa cc);

commit;
