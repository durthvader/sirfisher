-- =====================================================================
-- KPI de saldo projetado passa a ler o cálculo ao vivo
-- =====================================================================
--
-- PROBLEMA
--   Em 17/08/2026 o painel mostrava dois fechamentos diferentes para o
--   MESMO mês de agosto:
--
--     Calendário e gráfico do Caixa .......... R$ 170.334,28
--     KPI "Saldo projetado (fim do mês)" ....  R$  61.024,00
--
--   As duas telas liam fontes diferentes. O Calendário e o gráfico usam
--   `saldo_mensal_calculado` (view, recalculada a cada leitura). O KPI da
--   Visão Geral e do Caixa usa `app_painel_saldo_fim_mes`, que para o mês
--   corrente devolve o valor congelado na tabela `saldo_fechamento_mensal`.
--
--   Conferido no banco, o cálculo ao vivo fecha exatamente com o
--   Calendário (corte em 16/08):
--
--     109.310,28  âncora de saldo no corte
--    + 75.326,37  recebimento_conhecido
--    + 46.634,97  recebimento_projetado
--    - 40.205,42  projecao_despesa_direta
--    - 20.731,92  projecao_despesa_fixa
--    = 170.334,28
--
--   A linha congelada de agosto tinha sido gravada às 11:34 do mesmo dia,
--   durante uma importação, num instante em que as materialized views de
--   recebimento ainda não tinham sido atualizadas: 109.310,28 - 48.286,28
--   de despesa projetada, com as entradas zeradas, dá os R$ 61.024,00.
--
--   E o valor ficou preso, porque `recalcular_saldo_fechamento` só é
--   chamada pelos fluxos de importação e de conciliação. O cron horário
--   (`sirfisher-virada-financeira`) atualiza as materialized views e faz o
--   corte avançar, mas não regrava o snapshot. A view ao vivo andou; a
--   tabela não.
--
-- SOLUÇÃO
--   Mês projetado não deve ter valor congelado. `app_painel_saldo_fim_mes`
--   passa a ler `saldo_mensal_calculado` quando a situação é 'Projetado',
--   que é a mesma fonte do Calendário e do gráfico da própria página.
--
--   Meses fechados continuam vindo do último snapshot diário real, como já
--   vinham. Isso é intencional e NÃO deve ser unificado com o cálculo ao
--   vivo: para mês fechado a view caminha para trás a partir da âncora
--   usando `caixa_real_diario`, que não enxerga a conta "Dinheiro a
--   depositar". Em julho/2026 isso dá uma diferença de R$ 4.550,00
--   (140.357,22 real no extrato contra 144.907,22 caminhando para trás) --
--   exatamente a variação da espécie ainda não depositada no período. O
--   snapshot diário é a fonte correta para mês fechado.
--
-- OBJETOS
--   ~ public.app_painel_saldo_fim_mes  (view, mesmas colunas e tipos)
--
-- IMPACTO
--   - Mês corrente/futuro: passa a bater com o Calendário e com o gráfico.
--     Agosto/2026: R$ 61.024,00 -> R$ 170.334,28.
--   - Meses fechados: inalterados (mesmo COALESCE de antes).
--   - Nenhuma tabela é alterada; `saldo_fechamento_mensal` segue sendo
--     gravada pelos importadores e permanece como registro histórico.
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
)
select s.mes,
  s.ano_mes,
  case
    -- Mês fechado: o saldo real do extrato no último dia com dado.
    when s.mes < date_trunc('month', c.dia)::date
      then coalesce(u.saldo_total, s.saldo_fim)
    -- Mês em aberto: o mesmo cálculo que o Calendário exibe, nunca o
    -- snapshot congelado, que pode ter sido gravado no meio de uma
    -- importação.
    when s.situacao = 'Projetado'
      then coalesce(v.saldo_fim, s.saldo_fim)
    else s.saldo_fim
  end as saldo_fim,
  s.situacao
from public.painel_saldo_fim_mes s
cross join corte c
left join ultimo_snapshot_mes u on u.mes = s.mes
left join public.saldo_mensal_calculado v on v.mes = s.mes
where public.usuario_pode_acessar_alguma_pagina(array['index.html', 'caixa.html']);

grant select on public.app_painel_saldo_fim_mes to authenticated;

-- Confere o objeto efetivo, não apenas o texto desta migration.
do $validacao$
declare
  v_def text := pg_get_viewdef('public.app_painel_saldo_fim_mes'::regclass, true);
  v_divergencia numeric;
begin
  if position('saldo_mensal_calculado' in v_def) = 0 then
    raise exception 'O KPI de saldo projetado não passou a ler o cálculo ao vivo.';
  end if;

  if position('ultimo_snapshot_mes' in v_def) = 0 then
    raise exception 'A view perdeu o snapshot diário usado nos meses fechados.';
  end if;

  -- Mês projetado tem de bater com a fonte do Calendário.
  select max(abs(a.saldo_fim - v.saldo_fim)) into v_divergencia
  from public.painel_saldo_fim_mes a
  join public.saldo_mensal_calculado v on v.mes = a.mes
  where a.situacao = 'Projetado'
    and a.mes >= date_trunc('month', (select dia from public.corte_caixa))::date;

  if v_divergencia is not null and v_divergencia > 0.01 then
    raise notice 'Snapshot congelado divergia do cálculo ao vivo em R$ %', v_divergencia;
  end if;
end;
$validacao$;

comment on view public.app_painel_saldo_fim_mes is
  'Saldo de fechamento por mês para os painéis: mês fechado usa o saldo real do último snapshot diário; mês em aberto usa saldo_mensal_calculado ao vivo, a mesma fonte do Calendário, para não exibir snapshot gravado no meio de uma importação.';

commit;
