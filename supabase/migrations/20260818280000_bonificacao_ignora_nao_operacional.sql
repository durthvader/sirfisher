-- =====================================================================
-- Bonificação do gerente ignora movimento não operacional
-- =====================================================================
--
-- PROBLEMA
--   A previsão de bonificação usa a variação BRUTA do caixa como base:
--   `greatest(saldo_fim - saldo_anterior, 0) * percentual`, com teto. Ou
--   seja, qualquer movimento não operacional do sócio -- distribuição de
--   lucros, investimento financeiro, empréstimo -- reduz o bônus de quem
--   não decidiu nada sobre ele.
--
--   Medido por data de caixa, o efeito não é hipotético:
--
--     mês      variação   bônus hoje   não operacional   bônus sem ele
--     2026-08   25.427      508,54        -5.000,00         600,00
--     2026-07   22.194      443,89        -5.000,00         543,89
--     2026-06   14.881      297,61        -5.000,00         397,61
--     2026-05    5.819      116,38             0,00         116,38
--     2026-04    4.143       82,85       -44.299,98         600,00
--
--   Em abril o gerente ficou com R$ 82,85 por causa de R$ 44,3 mil de
--   movimento não operacional. E o `Investimento Financeiro` recorrente de
--   R$ 5.000 corta R$ 100 do bônus todos os meses.
--
-- SOLUÇÃO
--   A base da bonificação passa a somar de volta o que saiu (ou entrou) no
--   grupo `NÃO OPERACIONAL`. O plano de contas já tem as categorias certas
--   (`Distribuição de Lucros`, `Investimento Financeiro`, `Empréstimo`,
--   `Pagamento de Empréstimo`, ...), então classificar corretamente passa a
--   ser suficiente: saque extra lançado como distribuição de lucros não
--   afeta o bônus, sem ajuste manual nenhum.
--
--   A regra fica em `public.bonificacao_base_mes`, fonte única, para não
--   repetir o erro de espalhar a mesma conta por várias views.
--
--   `variacao_perc` NÃO muda: continua sendo a variação real do caixa, que
--   é um fato. Só a base do incentivo é ajustada. A view passa a expor
--   `ajuste_nao_operacional` e `base_bonificacao` para a tela poder
--   explicar o número ao gerente em vez de exibir um valor inexplicável.
--
-- POR QUE `data_caixa <= corte`
--   O ajuste só pode somar de volta o que o saldo JÁ absorveu. Movimento
--   lançado com data de caixa posterior ao corte ainda não reduziu
--   `saldo_fim` (a projeção só contém receita, despesa direta e despesa
--   fixa), então somá-lo de volta inflaria o bônus. Mesma regra que a
--   20260818180000 aplicou à despesa fixa; quando o corte avança, os dois
--   lados passam a contar juntos, sem degrau.
--
-- POR QUE `Pro Labore` FICA DENTRO (decisão do usuário)
--   Ele oscila entre R$ 12 mil e R$ 24 mil. Neutralizá-lo cravaria o bônus
--   no teto em quatro dos cinco meses medidos, e o incentivo pararia de
--   distinguir desempenho -- viraria salário fixo. Fica como custo do
--   negócio.
--
-- OBJETOS
--   + public.bonificacao_base_mes        (view nova, sem exposição na API)
--   ~ public.app_gerente_saldo_variacao  (+ ajuste_nao_operacional,
--                                         + base_bonificacao, no fim)
--
-- IMPACTO (agosto/2026)
--   previsão de bonificação: sobe ao teto, porque os R$ 5.000 de
--   investimento financeiro deixam de ser descontados.
--   `variacao_perc` e todas as outras telas: inalteradas.
--
-- PENDÊNCIA ANOTADA, não tratada aqui por escolha do usuário
--   A base compara medidas diferentes: mês em aberto vem do fluxo
--   projetado, mês fechado vem do snapshot diário, que inclui a espécie
--   ainda não depositada. Em agosto isso infla a variação em R$ 4.550
--   (~R$ 91 de bônus). Corrigir exige usar a mesma medida nos dois lados da
--   subtração e muda bônus de meses já fechados.
--
-- RISCO: baixo. Nenhuma tabela é alterada; `variacao_perc` não muda; as
--   colunas existentes mantêm nome, ordem e tipo.
-- =====================================================================

begin;

-- 1) A regra da base do bônus, num único lugar.
create or replace view public.bonificacao_base_mes as
with corte as (
  select dia from public.corte_caixa
), saldos as (
  select e.mes,
    e.ano_mes,
    e.saldo_fim,
    lag(e.saldo_fim) over (order by e.ano_mes) as saldo_anterior
  from public.saldo_fim_mes_efetivo e
), nao_operacional as (
  -- Só o que o saldo já absorveu: data de caixa dentro do corte.
  select date_trunc('month', f.data_caixa)::date as mes,
    round(sum(f.valor), 2) as valor
  from public.fato_financeiro f
  cross join corte ct
  where f.dre_grupo = 'NÃO OPERACIONAL'
    and f.data_caixa <= ct.dia
  group by 1
)
select s.mes,
  s.ano_mes,
  s.saldo_fim,
  s.saldo_anterior,
  round(s.saldo_fim - s.saldo_anterior, 2) as variacao_caixa,
  coalesce(n.valor, 0::numeric) as ajuste_nao_operacional,
  -- Somar de volta: os valores do grupo são negativos quando saem.
  round(s.saldo_fim - s.saldo_anterior - coalesce(n.valor, 0::numeric), 2) as base_bonificacao
from saldos s
left join nao_operacional n on n.mes = s.mes;

revoke all privileges on public.bonificacao_base_mes from public, anon, authenticated;

comment on view public.bonificacao_base_mes is
  'Base da bonificação do gerente: variação do caixa no mês menos os movimentos do grupo NÃO OPERACIONAL já absorvidos pelo caixa (data_caixa dentro do corte). Não expor na API -- ler pela view app_gerente_saldo_variacao.';

-- 2) A view do gerente passa a usar a base ajustada.
create or replace view public.app_gerente_saldo_variacao
with (security_barrier = true, security_invoker = false) as
select b.ano_mes,
  -- Fato, não incentivo: segue sendo a variação real do caixa.
  round(100.0 * b.variacao_caixa / nullif(abs(b.saldo_anterior), 0::numeric), 1) as variacao_perc,
  case
    when b.saldo_anterior is null then null::numeric
    else least(
      round(greatest(b.base_bonificacao, 0::numeric)
            * public.parametro_valor('bonus_gerente_percentual', 2::numeric) / 100::numeric, 2),
      public.parametro_valor('bonus_gerente_teto', 600::numeric))
  end as previsao_bonificacao,
  b.ajuste_nao_operacional,
  b.base_bonificacao
from public.bonificacao_base_mes b
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

grant select on public.app_gerente_saldo_variacao to authenticated;

-- Confere os objetos efetivos, não apenas o texto desta migration.
do $validacao$
declare
  v_def text := pg_get_viewdef('public.app_gerente_saldo_variacao'::regclass, true);
  v_mes date := date_trunc('month', (select dia from public.corte_caixa))::date;
  v_base record;
  v_futuro numeric;
begin
  if position('bonificacao_base_mes' in v_def) = 0 then
    raise exception 'A view do gerente não passou a ler a base única do bônus.';
  end if;

  -- A variação exibida tem de continuar sendo a variação BRUTA do caixa.
  if position('variacao_caixa' in v_def) = 0 then
    raise exception 'A variação exibida deixou de ser a variação real do caixa.';
  end if;

  select * into v_base from public.bonificacao_base_mes where mes = v_mes;

  if v_base.mes is null then
    raise exception 'A base do bônus não devolveu o mês corrente.';
  end if;

  -- O ajuste só vale se o caixa já absorveu o movimento. Nada com data de
  -- caixa além do corte pode entrar no ajuste.
  select round(coalesce(sum(f.valor), 0), 2) into v_futuro
  from public.fato_financeiro f
  where f.dre_grupo = 'NÃO OPERACIONAL'
    and f.data_caixa > (select dia from public.corte_caixa)
    and f.data_caixa < (v_mes + interval '1 month')::date;

  if v_futuro <> 0 and v_base.ajuste_nao_operacional = 0 then
    raise notice 'Há R$ % não operacional depois do corte; entra no ajuste quando o corte avançar.', v_futuro;
  end if;

  -- A identidade da base tem de fechar.
  if abs(v_base.base_bonificacao
         - (v_base.variacao_caixa - v_base.ajuste_nao_operacional)) > 0.01 then
    raise exception 'A base do bônus não fecha com a variação menos o ajuste.';
  end if;

  raise notice 'Base do bônus de %: variação R$ %, ajuste R$ %, base R$ %.',
    v_base.ano_mes, v_base.variacao_caixa, v_base.ajuste_nao_operacional,
    v_base.base_bonificacao;
end;
$validacao$;

commit;
