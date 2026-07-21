-- =====================================================================
-- Historico do Caixa usa a mesma memoria diaria do Calendario
-- =====================================================================
--
-- PROBLEMA
--   A curva historica, os fechamentos mensais e o saldo comparativo ainda
--   vinham das views antigas. Essas views reconstruiram o passado somando o
--   dinheiro pendente no corte atual, de modo que uma sangria ainda nao
--   depositada tambem elevava saldos de datas anteriores.
--
-- SOLUCAO
--   - usar mv_saldo_caixa_diario_detalhado nas linhas realizadas da curva;
--   - substituir fechamentos de meses encerrados pelo ultimo snapshot diario
--     disponivel daquele mes;
--   - substituir apenas o saldo comparativo pelo snapshot da data comparada;
--   - preservar saldo atual, mes corrente, projecoes e contratos app_*.
--
-- OBJETOS
--   ~ public.painel_fluxo_caixa
--   ~ public.app_painel_saldo_fim_mes
--   ~ public.app_painel_saldo_atual
--   ~ public.app_gerente_saldo_variacao
--
-- RISCO
--   Os valores historicos podem mudar porque passam a refletir a custodia
--   efetiva de cada data. Se nao existir snapshot para uma data ou mes, a view
--   conserva o valor anterior como fallback. DRE e projecoes nao sao alteradas.
-- =====================================================================

begin;

-- A curva mantem o snapshot/projecao ja materializado, mas troca somente as
-- linhas realizadas pela memoria diaria Stone + BB + especie da mesma data.
-- No ultimo dia realizado as duas fontes convergem; portanto, a continuidade
-- com as linhas projetadas e preservada.
create or replace view public.painel_fluxo_caixa as
select
  f.dia,
  f.tipo,
  case
    when f.tipo = 'real' then coalesce(d.saldo_total, f.saldo)
    else f.saldo
  end as saldo,
  case
    when f.tipo = 'real' then coalesce(d.saldo_total, f.saldo)
    else null::numeric
  end as saldo_real,
  case
    when f.tipo = 'projetado' then f.saldo
    else null::numeric
  end as saldo_projetado,
  f.entrada_projetada,
  f.saida_projetada,
  case
    when f.tipo = 'real'
      and d.dia is not null
      and f.resultado_dia is not null
      then round(
        f.resultado_dia + coalesce(d.variacao_dinheiro_pendente, 0::numeric),
        2
      )
    else f.resultado_dia
  end as resultado_dia
from public.mv_fluxo_caixa_diario f
left join public.mv_saldo_caixa_diario_detalhado d on d.dia = f.dia
order by f.dia;

comment on view public.painel_fluxo_caixa is
  'Curva de caixa: realizado usa o snapshot diario detalhado; projecao preserva a memoria prospectiva existente.';

-- Meses encerrados recebem o ultimo snapshot existente no proprio mes. O mes
-- do corte continua com a projecao original, inclusive quando ainda incompleto.
create or replace view public.app_painel_saldo_fim_mes
with (security_barrier = true, security_invoker = false) as
with corte as (
  select max(d.dia) as dia
  from public.mv_saldo_caixa_diario_detalhado d
), ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes,
    d.saldo_total
  from public.mv_saldo_caixa_diario_detalhado d
  order by date_trunc('month', d.dia)::date, d.dia desc
)
select
  s.mes,
  s.ano_mes,
  case
    when s.mes::date < date_trunc('month', c.dia)::date
      then coalesce(u.saldo_total, s.saldo_fim)
    else s.saldo_fim
  end as saldo_fim,
  s.situacao
from public.painel_saldo_fim_mes s
cross join corte c
left join ultimo_snapshot_mes u on u.mes = s.mes::date
where public.usuario_tem_papel(array['admin', 'socio']);

comment on view public.app_painel_saldo_fim_mes is
  'Fechamentos encerrados usam o snapshot diario do mes; mes corrente e projecoes preservam a fonte original.';

-- O saldo atual continua sendo a ancora corrente. Somente a comparacao volta
-- ao snapshot efetivamente existente na data_comp, sem reaplicar o pendente de
-- especie do corte atual ao passado.
create or replace view public.app_painel_saldo_atual
with (security_barrier = true, security_invoker = false) as
select
  s.data_ref,
  s.saldo_atual,
  s.data_comp,
  coalesce(comp.saldo_total, s.saldo_comp) as saldo_comp
from public.painel_saldo_atual s
left join lateral (
  select d.saldo_total
  from public.mv_saldo_caixa_diario_detalhado d
  where d.dia <= s.data_comp::date
  order by d.dia desc
  limit 1
) comp on true
where public.usuario_tem_papel(array['admin', 'socio']);

comment on view public.app_painel_saldo_atual is
  'Saldo atual preservado; comparacao usa o snapshot diario correspondente a data_comp.';

-- O painel do gerente mostra apenas a variacao percentual, mas deve partir dos
-- mesmos fechamentos corrigidos para nao manter uma leitura divergente.
create or replace view public.app_gerente_saldo_variacao
with (security_barrier = true, security_invoker = false) as
with corte as (
  select max(d.dia) as dia
  from public.mv_saldo_caixa_diario_detalhado d
), ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes,
    d.saldo_total
  from public.mv_saldo_caixa_diario_detalhado d
  order by date_trunc('month', d.dia)::date, d.dia desc
), saldos as (
  select
    s.ano_mes,
    case
      when s.mes::date < date_trunc('month', c.dia)::date
        then coalesce(u.saldo_total, s.saldo_fim)
      else s.saldo_fim
    end as saldo_fim
  from public.painel_saldo_fim_mes s
  cross join corte c
  left join ultimo_snapshot_mes u on u.mes = s.mes::date
)
select
  s.ano_mes,
  round(
    (
      100.0 * (s.saldo_fim - lag(s.saldo_fim) over (order by s.ano_mes))
        / nullif(abs(lag(s.saldo_fim) over (order by s.ano_mes)), 0)
    )::numeric,
    1
  ) as variacao_perc
from saldos s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

comment on view public.app_gerente_saldo_variacao is
  'Variacao percentual calculada com fechamentos historicos do snapshot diario.';

revoke all privileges on table
  public.app_painel_saldo_fim_mes,
  public.app_painel_saldo_atual,
  public.app_gerente_saldo_variacao
from public, anon, authenticated;

grant select on table
  public.app_painel_saldo_fim_mes,
  public.app_painel_saldo_atual,
  public.app_gerente_saldo_variacao
to authenticated;

commit;
