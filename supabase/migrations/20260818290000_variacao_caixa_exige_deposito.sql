-- =====================================================================
-- Variação do caixa exige depósito: espécie parada não conta
-- =====================================================================
--
-- REGRA DE NEGÓCIO (definida pelo usuário)
--   Dinheiro em espécie ainda não depositado NÃO entra na variação do caixa
--   do Painel do Gerente. É incentivo deliberado: o gerente deve depositar
--   com frequência e, sobretudo, antes de fechar o mês. Caixa que ficou na
--   gaveta não conta como caixa gerado.
--
--   O efeito é simétrico e auto-corretivo: a espécie parada no fim do mês
--   reduz aquele mês e aumenta o seguinte, quando finalmente é depositada.
--
-- EFEITO MEDIDO (conta espécie = saldo_adaptador 'venda_especie')
--   mês      espécie parada   variação antes   variação agora
--   2026-08     4.800,00         29.977,06        25.427,06
--   2026-07       250,00         19.144,27        22.194,27
--   2026-06     3.300,00         18.180,71        14.880,71
--   2026-05         0,00          5.819,23         5.819,23
--
--   Julho sobe porque quase tudo foi depositado; junho cai porque fechou com
--   R$ 3.300 na gaveta. É o incentivo funcionando.
--
-- GANHO LATERAL: resolve a pendência anotada na 20260818280000
--   A base comparava medidas diferentes -- mês em aberto vinha do fluxo
--   projetado (que não enxerga espécie) e mês fechado vinha do snapshot
--   diário (que enxerga). Isso inflava agosto em R$ 4.550. Excluindo a
--   espécie dos DOIS lados da subtração, o degrau desaparece: a variação de
--   agosto passa a ser exatamente os R$ 25.427,06 que o fluxo mede.
--
-- MOMENTO DA MEDIÇÃO
--   O saldo de espécie é lido no último dia do mês que já esteja dentro do
--   corte de caixa. Em mês fechado isso é o fim do mês; no mês em aberto é o
--   próprio corte -- que é coerente, porque a projeção carrega o saldo de
--   espécie do corte e não modela acúmulo futuro.
--
-- ESCOPO: só a variação e a base do bônus do Painel do Gerente.
--   A página Caixa continua mostrando o saldo TOTAL, espécie incluída, em
--   "Onde está o dinheiro" e na curva de saldo. Ali o número é um fato sobre
--   onde o dinheiro está, não um incentivo, e não deve mudar.
--
-- OBJETOS
--   ~ public.bonificacao_base_mes       (variacao_caixa passa a ser
--                                        ex-espécie; + colunas de auditoria)
--   ~ public.app_gerente_saldo_variacao (mesmas colunas; denominador do
--                                        percentual também ex-espécie)
--
-- RISCO: baixo. Nenhuma tabela é alterada. A conta de espécie é identificada
--   por `saldo_adaptador = 'venda_especie'`, não por nome, então renomear a
--   conta não quebra a regra.
-- =====================================================================

begin;

create or replace view public.bonificacao_base_mes as
with corte as (
  select dia from public.corte_caixa
), conta_especie as (
  select conta_id
  from public.fonte_financeira
  where saldo_adaptador = 'venda_especie' and conta_id is not null
), especie_mes as (
  -- Último dia de cada mês que já está dentro do corte: fim do mês nos meses
  -- fechados, o próprio corte no mês em aberto.
  select distinct on (date_trunc('month', s.dia)::date)
    date_trunc('month', s.dia)::date as mes,
    s.saldo
  from private.mv_saldo_conta_diario s
  cross join corte ct
  where s.conta_id in (select conta_id from conta_especie)
    and s.dia <= ct.dia
  order by date_trunc('month', s.dia)::date, s.dia desc
), saldos as (
  select e.mes,
    e.ano_mes,
    e.saldo_fim,
    coalesce(em.saldo, 0::numeric) as especie_fim,
    -- Espécie parada não é caixa gerado: sai dos dois lados da subtração.
    round(e.saldo_fim - coalesce(em.saldo, 0::numeric), 2) as saldo_fim_liquido
  from public.saldo_fim_mes_efetivo e
  left join especie_mes em on em.mes = e.mes
), comparacao as (
  select s.mes,
    s.ano_mes,
    s.saldo_fim,
    s.especie_fim,
    s.saldo_fim_liquido,
    lag(s.saldo_fim) over (order by s.ano_mes) as saldo_anterior,
    lag(s.saldo_fim_liquido) over (order by s.ano_mes) as saldo_anterior_liquido
  from saldos s
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
select c.mes,
  c.ano_mes,
  c.saldo_fim,
  c.saldo_anterior,
  -- Variação do caixa para fins de incentivo: sem a espécie ainda na gaveta.
  round(c.saldo_fim_liquido - c.saldo_anterior_liquido, 2) as variacao_caixa,
  coalesce(n.valor, 0::numeric) as ajuste_nao_operacional,
  round(c.saldo_fim_liquido - c.saldo_anterior_liquido
        - coalesce(n.valor, 0::numeric), 2) as base_bonificacao,
  c.especie_fim,
  c.saldo_fim_liquido,
  c.saldo_anterior_liquido
from comparacao c
left join nao_operacional n on n.mes = c.mes;

revoke all privileges on public.bonificacao_base_mes from public, anon, authenticated;

comment on view public.bonificacao_base_mes is
  'Base da bonificação do gerente. variacao_caixa exclui a espécie ainda não depositada nos dois lados da subtração (incentivo a depositar antes de fechar o mês) e base_bonificacao soma de volta o grupo NÃO OPERACIONAL. Não expor na API -- ler pela view app_gerente_saldo_variacao.';

-- O percentual precisa do mesmo denominador, senão mistura as medidas.
create or replace view public.app_gerente_saldo_variacao
with (security_barrier = true, security_invoker = false) as
select b.ano_mes,
  round(100.0 * b.variacao_caixa
        / nullif(abs(b.saldo_anterior_liquido), 0::numeric), 1) as variacao_perc,
  case
    when b.saldo_anterior_liquido is null then null::numeric
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
  v_base text := pg_get_viewdef('public.bonificacao_base_mes'::regclass, true);
  v_ger text := pg_get_viewdef('public.app_gerente_saldo_variacao'::regclass, true);
  v_mes date := date_trunc('month', (select dia from public.corte_caixa))::date;
  v_row record;
  v_especie_conta smallint;
begin
  -- A conta de espécie tem de ser resolvida por adaptador, não por nome.
  select conta_id into v_especie_conta
  from public.fonte_financeira
  where saldo_adaptador = 'venda_especie' and conta_id is not null;

  if v_especie_conta is null then
    raise exception 'Não há conta com saldo_adaptador venda_especie; a regra não teria efeito.';
  end if;

  if position('venda_especie' in v_base) = 0 then
    raise exception 'A base do bônus não passou a excluir a espécie.';
  end if;

  if position('saldo_anterior_liquido' in v_ger) = 0 then
    raise exception 'O percentual do gerente ainda usa denominador com espécie.';
  end if;

  select * into v_row from public.bonificacao_base_mes where mes = v_mes;

  if v_row.mes is null then
    raise exception 'A base do bônus não devolveu o mês corrente.';
  end if;

  -- Identidades: líquido = total - espécie, e base = variação - ajuste.
  if abs(v_row.saldo_fim_liquido - (v_row.saldo_fim - v_row.especie_fim)) > 0.01 then
    raise exception 'O saldo líquido não fecha com o total menos a espécie.';
  end if;

  if abs(v_row.base_bonificacao
         - (v_row.variacao_caixa - v_row.ajuste_nao_operacional)) > 0.01 then
    raise exception 'A base do bônus não fecha com a variação menos o ajuste.';
  end if;

  -- A espécie nunca pode ser negativa: indicaria depósito sem venda de origem.
  if exists (select 1 from public.bonificacao_base_mes where especie_fim < 0) then
    raise exception 'Saldo de espécie negativo em algum mês; verificar conferência de depósito.';
  end if;

  raise notice 'Variação sem espécie em %: R$ % (espécie parada R$ %), base R$ %.',
    v_row.ano_mes, v_row.variacao_caixa, v_row.especie_fim, v_row.base_bonificacao;
end;
$validacao$;

commit;
