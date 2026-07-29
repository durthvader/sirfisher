-- =====================================================================
-- Painel do gerente: previsao de bonificacao sobre a variacao do caixa
-- =====================================================================
--
-- PROBLEMA
--   gerente.html recebe somente a variacao percentual do caixa. O novo card
--   precisa calcular, em reais:
--
--     previsao de bonificacao
--       = (saldo final do mes - saldo final do mes anterior) * 0,02
--
-- SOLUCAO
--   Recriar app_gerente_saldo_variacao a partir de sua definicao mais
--   recente (snapshots historicos para meses fechados e saldo projetado para
--   o mes aberto) e acrescentar apenas previsao_bonificacao. A bonificacao
--   tem piso zero: queda do caixa nao gera valor negativo.
--
-- SEGURANCA E RISCO
--   A view nao expoe os saldos absolutos, mas a nova parcela permite inferir
--   a variacao em reais ao dividi-la por 0,02. Mantem security_barrier=true,
--   security_invoker=false, gate de papel e select somente para authenticated.
--   Nenhuma tabela ou lancamento e alterado.
-- =====================================================================

begin;

create or replace view public.app_gerente_saldo_variacao
with (security_barrier = true, security_invoker = false) as
with corte as (
  select max(d.dia) as dia
  from public.mv_saldo_caixa_diario_detalhado d
),
ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes,
    d.saldo_total
  from public.mv_saldo_caixa_diario_detalhado d
  order by date_trunc('month', d.dia)::date, d.dia desc
),
saldos as (
  select
    s.ano_mes,
    case
      when s.mes < date_trunc('month', c.dia)::date
        then coalesce(u.saldo_total, s.saldo_fim)
      else s.saldo_fim
    end as saldo_fim
  from public.painel_saldo_fim_mes s
  cross join corte c
  left join ultimo_snapshot_mes u on u.mes = s.mes
),
comparacao as (
  select
    s.ano_mes,
    s.saldo_fim,
    lag(s.saldo_fim) over (order by s.ano_mes) as saldo_anterior
  from saldos s
)
select
  c.ano_mes,
  round(
    100.0 * (c.saldo_fim - c.saldo_anterior)
      / nullif(abs(c.saldo_anterior), 0::numeric),
    1
  ) as variacao_perc,
  case
    when c.saldo_anterior is null then null::numeric
    else round(
      (greatest(c.saldo_fim - c.saldo_anterior, 0::numeric) * 0.02)::numeric,
      2
    )
  end as previsao_bonificacao
from comparacao c
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

comment on view public.app_gerente_saldo_variacao is
  'Variacao percentual do caixa e previsao de bonificacao de 2% sobre a variacao positiva em reais, com piso zero; nao expoe saldos absolutos.';

revoke all privileges on table public.app_gerente_saldo_variacao
from public, anon, authenticated;

grant select on table public.app_gerente_saldo_variacao
to authenticated;

commit;
