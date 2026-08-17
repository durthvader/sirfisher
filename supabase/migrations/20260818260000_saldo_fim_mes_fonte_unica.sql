-- =====================================================================
-- Saldo de fechamento por mês passa a ter fonte única
-- =====================================================================
--
-- PROBLEMA
--   O Painel do Gerente continuava mostrando "Variação do caixa ▼ 56,5%" e
--   "Previsão de bonificação R$ 0,00" depois das correções 20260818240000 e
--   20260818250000, que arrumaram só o KPI da Visão Geral e do Caixa.
--
--   Motivo: `app_gerente_saldo_variacao` REIMPLEMENTA a mesma conta de
--   fechamento mensal -- mesmo `corte`, mesmo `ultimo_snapshot_mes`, mesmo
--   `painel_saldo_fim_mes` -- e a cópia ficou com o comportamento antigo
--   (`else s.saldo_fim`), lendo o snapshot congelado de agosto.
--
--   Os R$ 61.024,00 congelados contra os R$ 140.357,22 de julho dão
--   exatamente os -56,5% exibidos. E como a bonificação é
--   `greatest(saldo - saldo_anterior, 0) * percentual`, a queda artificial
--   zerava o bônus do gerente: R$ 0,00 em vez de R$ 599,54.
--
--   A busca por consumidores na 20260818240000 usou `pg_depend`, que
--   registra dependência de view mas NÃO enxerga lógica duplicada em outra
--   view nem corpo de função. A cópia passou invisível.
--
-- SOLUÇÃO
--   Extrair a regra para uma view única, `public.saldo_fim_mes_efetivo`, e
--   fazer as duas views `app_*` lerem dela, cada uma com o seu gate de
--   papel. Assim o comportamento deixa de ser copiável: corrigir a regra
--   passa a corrigir todas as telas de uma vez.
--
--   A regra permanece a mesma já validada:
--     - mês fechado  -> saldo real do último snapshot diário
--                       (o fluxo caminha para trás sem enxergar "Dinheiro a
--                        depositar"; em julho/2026 erraria R$ 4.550,00);
--     - mês em aberto -> saldo do último dia em `mv_fluxo_caixa_diario`, a
--                       mesma fonte materializada do Calendário.
--
-- OBJETOS
--   + public.saldo_fim_mes_efetivo      (view nova, sem exposição na API)
--   ~ public.app_painel_saldo_fim_mes   (view, mesmas colunas e tipos)
--   ~ public.app_gerente_saldo_variacao (view, mesmas colunas e tipos)
--
-- IMPACTO MEDIDO (agosto/2026, corte em 16/08)
--   Painel do Gerente:
--     variação do caixa ......  -56,5%  ->  +21,4%
--     previsão de bonificação   R$ 0,00 ->  R$ 599,54
--   Visão Geral e Caixa: inalterados, seguem em R$ 170.334,28.
--   Meses fechados: inalterados.
--
-- SEGURANÇA
--   `saldo_fim_mes_efetivo` não recebe grant para `anon`/`authenticated` --
--   é lida apenas pelas views `app_*`, que rodam com
--   `security_invoker = false` e têm o gate de papel no WHERE, exatamente o
--   padrão que o AGENTS.md documenta. Os gates de cada tela ficam
--   preservados: páginas para o painel, papéis para o gerente.
--
-- RISCO: baixo. Nenhuma tabela é alterada, nenhuma coluna, tipo, grant ou
--   gate muda. A regra de cálculo é a que já está em produção.
-- =====================================================================

begin;

-- 1) A regra, num único lugar.
create or replace view public.saldo_fim_mes_efetivo as
with corte as (
  select max(d.dia) as dia from private.saldo_caixa_diario d
), ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes,
    d.saldo_total
  from private.saldo_caixa_diario d
  order by date_trunc('month', d.dia)::date, d.dia desc
), fechamento_fluxo as (
  select distinct on (f.mes) f.mes, f.saldo
  from public.mv_fluxo_caixa_diario f
  order by f.mes, f.dia desc
)
select s.mes,
  s.ano_mes,
  case
    -- Mês fechado: saldo real do extrato no último dia com dado.
    when s.mes < date_trunc('month', c.dia)::date
      then coalesce(u.saldo_total, s.saldo_fim)
    -- Mês em aberto: o mesmo fluxo materializado que alimenta o Calendário,
    -- nunca o snapshot congelado, que pode ter sido gravado no meio de uma
    -- importação.
    when s.situacao = 'Projetado'
      then coalesce(ff.saldo, s.saldo_fim)
    else s.saldo_fim
  end as saldo_fim,
  s.situacao
from public.painel_saldo_fim_mes s
cross join corte c
left join ultimo_snapshot_mes u on u.mes = s.mes
left join fechamento_fluxo ff on ff.mes = s.mes;

-- Fonte interna: quem expõe são as views app_*, com o gate de papel.
revoke all privileges on public.saldo_fim_mes_efetivo from public, anon, authenticated;

comment on view public.saldo_fim_mes_efetivo is
  'Fonte única do saldo de fechamento por mês: mês fechado usa o snapshot diário real, mês em aberto usa mv_fluxo_caixa_diario. Não expor na API -- ler pelas views app_*, que carregam o gate de papel.';

-- 2) KPI da Visão Geral e do Caixa.
create or replace view public.app_painel_saldo_fim_mes
with (security_barrier = true, security_invoker = false) as
select e.mes,
  e.ano_mes,
  e.saldo_fim,
  e.situacao
from public.saldo_fim_mes_efetivo e
where public.usuario_pode_acessar_alguma_pagina(array['index.html', 'caixa.html']);

grant select on public.app_painel_saldo_fim_mes to authenticated;

-- 3) Painel do Gerente. Mesma fonte, gate próprio.
create or replace view public.app_gerente_saldo_variacao
with (security_barrier = true, security_invoker = false) as
with comparacao as (
  select e.ano_mes,
    e.saldo_fim,
    lag(e.saldo_fim) over (order by e.ano_mes) as saldo_anterior
  from public.saldo_fim_mes_efetivo e
)
select c.ano_mes,
  round(100.0 * (c.saldo_fim - c.saldo_anterior)
        / nullif(abs(c.saldo_anterior), 0::numeric), 1) as variacao_perc,
  case
    when c.saldo_anterior is null then null::numeric
    else least(
      round(greatest(c.saldo_fim - c.saldo_anterior, 0::numeric)
            * public.parametro_valor('bonus_gerente_percentual', 2::numeric) / 100::numeric, 2),
      public.parametro_valor('bonus_gerente_teto', 600::numeric))
  end as previsao_bonificacao
from comparacao c
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

grant select on public.app_gerente_saldo_variacao to authenticated;

-- Confere os objetos efetivos, não apenas o texto desta migration.
do $validacao$
declare
  v_painel text := pg_get_viewdef('public.app_painel_saldo_fim_mes'::regclass, true);
  v_gerente text := pg_get_viewdef('public.app_gerente_saldo_variacao'::regclass, true);
  v_duplicadas text;
  v_mes date := date_trunc('month', (select dia from public.corte_caixa))::date;
  v_esperado numeric;
  v_variacao numeric;
begin
  -- As duas telas têm de ler a fonte única.
  if position('saldo_fim_mes_efetivo' in v_painel) = 0 then
    raise exception 'O KPI do painel não passou a ler a fonte única.';
  end if;

  if position('saldo_fim_mes_efetivo' in v_gerente) = 0 then
    raise exception 'O painel do gerente não passou a ler a fonte única.';
  end if;

  -- E nenhuma delas pode voltar a replicar a regra.
  if position('ultimo_snapshot_mes' in v_painel) > 0
     or position('ultimo_snapshot_mes' in v_gerente) > 0 then
    raise exception 'Uma view app_* voltou a replicar a regra de fechamento.';
  end if;

  -- Guarda contra o defeito que originou esta migration: qualquer OUTRA view
  -- que leia painel_saldo_fim_mes direto é uma cópia esperando divergir.
  select string_agg(n.nspname || '.' || c.relname, ', ')
    into v_duplicadas
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('v', 'm')
    and n.nspname in ('public', 'private')
    and c.relname <> 'saldo_fim_mes_efetivo'
    and pg_get_viewdef(c.oid, true) ilike '%painel_saldo_fim_mes%';

  if v_duplicadas is not null then
    raise exception
      'Estas views ainda leem painel_saldo_fim_mes direto, em vez da fonte única: %',
      v_duplicadas;
  end if;

  -- O gerente tem de ver a variação coerente com o fechamento corrigido.
  select e.saldo_fim into v_esperado
  from public.saldo_fim_mes_efetivo e where e.mes = v_mes;

  if v_esperado is null then
    raise exception 'A fonte única não devolveu o mês corrente.';
  end if;

  select round(100.0 * (v_esperado - lag_saldo) / nullif(abs(lag_saldo), 0), 1)
    into v_variacao
  from (
    select e.saldo_fim as lag_saldo from public.saldo_fim_mes_efetivo e
    where e.mes = (v_mes - interval '1 month')::date
  ) anterior;

  if v_variacao is null then
    raise exception 'Não foi possível calcular a variação do mês corrente.';
  end if;

  if v_variacao < 0 and v_esperado > 100000 then
    raise exception
      'Variação do mês corrente ficou negativa (%) com saldo de R$ % -- sinal de snapshot congelado.',
      v_variacao, v_esperado;
  end if;

  raise notice 'Fonte única ativa. Mês corrente: R$ %, variação % por cento.',
    v_esperado, v_variacao;
end;
$validacao$;

commit;
