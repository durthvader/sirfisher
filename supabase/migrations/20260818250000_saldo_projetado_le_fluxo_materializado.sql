-- =====================================================================
-- Saldo projetado lê o fluxo materializado, não a view ao vivo
-- =====================================================================
--
-- PROBLEMA
--   A migration 20260818240000 corrigiu o valor do KPI de saldo projetado
--   (mês em aberto passou a vir de `saldo_mensal_calculado` em vez do
--   snapshot congelado), mas ligou o painel numa view caríssima. Medido em
--   produção depois de aplicar:
--
--     select ... from public.saldo_mensal_calculado order by mes
--       Planning Time:   4.784,772 ms
--       Execution Time: 27.774,243 ms
--
--   O front-end pede a série inteira de meses de uma vez, então a leitura
--   estourava o timeout e o painel passou a exibir "Alguns indicadores
--   ficaram indisponíveis: saldo projetado", com o KPI em branco. Trocamos
--   um número errado por nenhum número -- pior que o estado anterior.
--
--   É exatamente o risco que o AGENTS.md registra sobre timeout nas views
--   `app_*`: `saldo_mensal_calculado` recalcula recebimento conhecido,
--   recebimento projetado e as duas projeções de despesa para todos os
--   meses, a cada leitura.
--
-- SOLUÇÃO
--   Ler o saldo de fechamento de `public.mv_fluxo_caixa_diario`, que é
--   materializada e já contém o saldo acumulado por dia: o fechamento do
--   mês é o `saldo` do último dia do mês. Mesmos números, custo trivial.
--
--     select distinct on (mes) mes, saldo ... order by mes, dia desc
--       Planning Time:  0,329 ms
--       Execution Time: 0,562 ms
--
--   Conferido valor a valor contra a view ao vivo antes da troca:
--     2026-07  144.907,22 = 144.907,22
--     2026-08  170.334,28 = 170.334,28   <- o KPI de agosto
--     2026-09  170.426,10 = 170.426,10
--
--   Ganho lateral: é a MESMA fonte que o Calendário e o gráfico do Caixa
--   consomem. O KPI passa a divergir do Calendário por construção
--   impossível, que era o defeito original desta série de migrations.
--
--   A materialized view é atualizada de hora em hora por
--   `private.processar_virada_financeira()`, junto com o avanço do corte.
--
-- OBJETOS
--   ~ public.app_painel_saldo_fim_mes  (view, mesmas colunas e tipos)
--
-- IMPACTO
--   - Mês em aberto: valor idêntico ao da 20260818240000, mas dentro do
--     timeout. Agosto/2026: KPI em branco -> R$ 170.334,28.
--   - Mês fechado: inalterado, continua vindo do último snapshot diário
--     real. Isso segue sendo intencional -- para mês fechado o fluxo
--     caminha para trás sem enxergar a conta "Dinheiro a depositar", o que
--     em julho/2026 dá R$ 4.550,00 de diferença (140.357,22 real contra
--     144.907,22 no fluxo). O snapshot é a fonte correta ali.
--
-- RISCO: baixo. Só troca a origem de leitura de uma view, sem mudar
--   colunas, tipos, grants, policies ou o gate de papel no WHERE.
-- =====================================================================

begin;

create or replace view public.app_painel_saldo_fim_mes
with (security_barrier = true, security_invoker = false) as
with corte as (
  select max(d.dia) as dia from private.saldo_caixa_diario d
), ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes,
    d.saldo_total
  from private.saldo_caixa_diario d
  order by date_trunc('month', d.dia)::date, d.dia desc
), fechamento_fluxo as (
  -- Saldo acumulado no último dia de cada mês, já materializado.
  select distinct on (f.mes) f.mes, f.saldo
  from public.mv_fluxo_caixa_diario f
  order by f.mes, f.dia desc
)
select s.mes,
  s.ano_mes,
  case
    -- Mês fechado: o saldo real do extrato no último dia com dado.
    when s.mes < date_trunc('month', c.dia)::date
      then coalesce(u.saldo_total, s.saldo_fim)
    -- Mês em aberto: o mesmo fluxo materializado que alimenta o Calendário
    -- e o gráfico, nunca o snapshot congelado, que pode ter sido gravado
    -- no meio de uma importação.
    when s.situacao = 'Projetado'
      then coalesce(ff.saldo, s.saldo_fim)
    else s.saldo_fim
  end as saldo_fim,
  s.situacao
from public.painel_saldo_fim_mes s
cross join corte c
left join ultimo_snapshot_mes u on u.mes = s.mes
left join fechamento_fluxo ff on ff.mes = s.mes
where public.usuario_pode_acessar_alguma_pagina(array['index.html', 'caixa.html']);

grant select on public.app_painel_saldo_fim_mes to authenticated;

-- Confere o objeto efetivo, não apenas o texto desta migration.
do $validacao$
declare
  v_def text := pg_get_viewdef('public.app_painel_saldo_fim_mes'::regclass, true);
  v_divergencia numeric;
begin
  if position('mv_fluxo_caixa_diario' in v_def) = 0 then
    raise exception 'O KPI de saldo projetado não passou a ler o fluxo materializado.';
  end if;

  if position('saldo_mensal_calculado' in v_def) > 0 then
    raise exception 'A view ainda lê saldo_mensal_calculado, que estoura o timeout.';
  end if;

  if position('ultimo_snapshot_mes' in v_def) = 0 then
    raise exception 'A view perdeu o snapshot diário usado nos meses fechados.';
  end if;

  -- O mês corrente é o que o KPI exibe e é onde a divergência original
  -- apareceu, então esse tem de bater ao centavo com o cálculo ao vivo.
  select abs(v.saldo_fim - ff.saldo) into v_divergencia
  from public.saldo_mensal_calculado v
  join (
    select distinct on (f.mes) f.mes, f.saldo
    from public.mv_fluxo_caixa_diario f
    order by f.mes, f.dia desc
  ) ff on ff.mes = v.mes
  where v.mes = date_trunc('month', (select dia from public.corte_caixa))::date;

  if v_divergencia is null then
    raise exception 'O mês corrente não está no fluxo materializado; refresh pendente?';
  end if;

  if v_divergencia > 0.01 then
    raise exception
      'Fechamento do mês corrente divergiu do cálculo ao vivo em R$ % -- refresh pendente.',
      v_divergencia;
  end if;

  -- Meses distantes podem defasar entre refreshes da materialized view.
  -- Isso é inerente a usar MV e não invalida o KPI, então só avisa. Medido
  -- na aplicação: fev/2027 divergia R$ 252,22, seis meses à frente.
  select max(abs(v.saldo_fim - ff.saldo)) into v_divergencia
  from public.saldo_mensal_calculado v
  join (
    select distinct on (f.mes) f.mes, f.saldo
    from public.mv_fluxo_caixa_diario f
    order by f.mes, f.dia desc
  ) ff on ff.mes = v.mes
  where v.situacao = 'Projetado'
    and v.mes > date_trunc('month', (select dia from public.corte_caixa))::date;

  if coalesce(v_divergencia, 0) > 0.01 then
    raise notice
      'Defasagem da MV em meses futuros: até R$ % -- esperado entre refreshes.',
      v_divergencia;
  end if;
end;
$validacao$;

comment on view public.app_painel_saldo_fim_mes is
  'Saldo de fechamento por mês para os painéis: mês fechado usa o saldo real do último snapshot diário; mês em aberto usa o saldo do último dia em mv_fluxo_caixa_diario, a mesma fonte materializada do Calendário, para não divergir do Calendário nem estourar o timeout.';

commit;
