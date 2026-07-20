-- =====================================================================
-- Dinheiro em especie pendente de deposito entra no caixa
-- =====================================================================
--
-- PROBLEMA
--   O saldo_anchor (base de todo o caixa e das projecoes) so soma banco:
--   saldo Stone (saldo_depois do extrato) + saldo BB. O dinheiro em especie
--   que a empresa JA tem fisicamente (recolhido no quiosque, ainda nao
--   depositado) fica de fora ate cair no extrato do BB. Resultado: o caixa
--   exibido subestima o que a empresa realmente tem em maos.
--
--   A tabela venda_especie ja rastreia o ciclo de vida (recolhida_em,
--   depositada_em), entao "pendente de deposito" = depositada_em IS NULL.
--   Esse dinheiro em maos ficava fora do saldo exibido.
--
-- SOLUCAO (aditiva; nao mexe em nenhuma regra de projecao)
--   1. saldo_anchor ganha a coluna dinheiro_pendente e passa a inclui-la no
--      saldo_total. Como saldo_mensal_calculado e fluxo_caixa_diario leem
--      saldo_anchor.saldo_total, a projecao inteira sobe pelo pendente
--      automaticamente, e o KPI "Saldo atual" (via painel_saldo_atual)
--      tambem. A coluna nova entra NO FIM da lista de colunas de propósito:
--      "create or replace view" so aceita acrescentar coluna no final, sem
--      reordenar as existentes.
--   2. painel_saldo_por_conta ganha a linha "Dinheiro a depositar" (apenas
--      quando ha pendente), entao a tela "Onde esta o dinheiro" da caixa.html
--      mostra a nova conta sem precisar mexer no HTML (drawContas ja renderiza
--      as linhas genericamente e corConta ja pinta "dinheiro" de marrom).
--
-- SEM CONTAGEM DUPLA
--   As vendas ja depositadas tem depositada_em preenchido e aparecem no
--   extrato do BB (ja contadas em saldo_bb); as pendentes NAO estao no BB.
--   venda_especie tambem nao entra em fato_financeiro/caixa_real_diario.
--   Quando o pendente for depositado e marcado (depositada_em), sai daqui e
--   entra no BB — a grana so troca de bolso, o total nao muda.
--
-- RISCO: baixo.
--   - Aditivo; nenhuma regra de projecao ou de despesa e alterada.
--   - Todo numero de caixa/projecao sobe pelo pendente (intencional).
--   - Atencao OPERACIONAL: se um lancamento ja depositado ficar sem
--     depositada_em, ele passa a contar em dobro (BB + pendente) ate ser
--     marcado. Manter a marcacao de deposito em dia evita isso.
--   - So reflete apos refresh do mv_fluxo_caixa_diario e recalculo do
--     snapshot de saldo — use "Atualizar tudo agora" em status.html.
--
-- OBJETOS
--   ~ public.saldo_anchor            (+ coluna dinheiro_pendente no fim)
--   ~ public.painel_saldo_por_conta  (+ linha "Dinheiro a depositar")
-- =====================================================================

begin;

-- 1. saldo_anchor: soma o dinheiro em especie pendente de deposito.
create or replace view public.saldo_anchor as
with corte as (
  select dia from public.corte_caixa limit 1
),
calc as (
  select
    (select dia from corte) as data_ref,
    coalesce((
      select e.saldo_depois
      from public.raw_stone_extrato e
      where e.saldo_depois is not null
        and e.data_hora::date <= (select dia from corte)
      order by e.data_hora desc nulls last
      limit 1
    ), 0::numeric) as saldo_stone,
    coalesce((
      select si.saldo from public.saldo_inicial si where lower(si.conta) = 'bb' limit 1
    ), 0::numeric)
    + coalesce((
      select sum(b.valor) from public.raw_bb b where b.data <= (select dia from corte)
    ), 0::numeric) as saldo_bb,
    coalesce((
      select sum(v.valor)
      from public.venda_especie v
      where v.depositada_em is null
        and v.unidade = 'PRAIA'
        and v.data <= (select dia from corte)
    ), 0::numeric) as dinheiro_pendente
)
select
  data_ref,
  round(saldo_stone, 2) as saldo_stone,
  round(saldo_bb, 2) as saldo_bb,
  -- saldo_total mantem a posicao 4 (nao pode reordenar em create or replace)
  round(saldo_stone + saldo_bb + dinheiro_pendente, 2) as saldo_total,
  -- coluna nova acrescentada no fim
  round(dinheiro_pendente, 2) as dinheiro_pendente
from calc;

-- 2. painel_saldo_por_conta: mostra o dinheiro a depositar como uma "conta".
create or replace view public.painel_saldo_por_conta as
select 'Stone'::text as conta, s.saldo_stone as saldo, s.data_ref
  from public.saldo_anchor s
union all
select 'Banco do Brasil'::text, s.saldo_bb, s.data_ref
  from public.saldo_anchor s
union all
select 'Dinheiro a depositar'::text, s.dinheiro_pendente, s.data_ref
  from public.saldo_anchor s
 where s.dinheiro_pendente <> 0;

commit;
