-- =====================================================================
-- Neutralização do bônus por categoria, não pelo grupo inteiro
-- =====================================================================
--
-- CORREÇÃO DE ESCOPO (definida pelo usuário)
--   A 20260818280000 tirou da base do bônus o grupo `NÃO OPERACIONAL`
--   INTEIRO. Era largo demais: o usuário quer neutralizar apenas
--   `Distribuição de Lucros`.
--
--   Consequência aceita: `Investimento Financeiro` (R$ 5.000/mês) e
--   `Pagamento de Empréstimo` voltam a contar contra o gerente.
--
-- COMO
--   `categoria_dre` ganha a flag `neutra_bonificacao`, no mesmo espírito de
--   `grupo_variavel`. A regra passa a ler a flag em vez de ter nome de
--   categoria ou de grupo escrito dentro da view. Mudar o critério vira um
--   `update` de uma linha, sem migration:
--
--     update public.categoria_dre set neutra_bonificacao = true
--      where categoria = 'Pagamento de Empréstimo';
--
--   Só `Distribuição de Lucros` começa marcada.
--
-- EFEITO MEDIDO
--   ago/2026: ajuste vai de -5.000,00 para 0,00; base cai de 30.427,06 para
--             25.427,06 e o bônus sai do teto (R$ 600,00) para R$ 508,54.
--   abr/2026: inalterado -- os R$ 44.299,98 de abril ERAM
--             `Distribuição de Lucros`, então aquele caso continua coberto.
--
-- ATENÇÃO, medido e não tratado
--   Agosto tem `Pagamento de Empréstimo` de R$ 17.890,64 com data de caixa
--   POSTERIOR ao corte. Quando o corte avançar, ele entra na variação e
--   reduz o bônus em ~R$ 358, porque a categoria não está marcada como
--   neutra. Se a intenção for poupar o gerente de amortização de dívida,
--   basta marcar a categoria com o `update` acima.
--
-- OBJETOS
--   + public.categoria_dre.neutra_bonificacao (coluna, default false)
--   ~ public.bonificacao_base_mes             (lê a flag; mesmas colunas)
--
-- RISCO: baixo. A coluna nasce com default false, então nenhuma categoria é
--   neutralizada por acidente; só a marcada explicitamente. A exclusão da
--   espécie da 20260818290000 não é alterada.
-- =====================================================================

begin;

alter table public.categoria_dre
  add column if not exists neutra_bonificacao boolean not null default false;

comment on column public.categoria_dre.neutra_bonificacao is
  'Quando true, a categoria é somada de volta na base da bonificação do gerente: é decisão do sócio, não resultado da operação. Marcar apenas o que o gerente não controla.';

update public.categoria_dre
   set neutra_bonificacao = true
 where categoria = 'Distribuição de Lucros'
   and neutra_bonificacao is distinct from true;

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
), neutro as (
  -- Categorias marcadas como neutras, e só o que o caixa já absorveu
  -- (data_caixa dentro do corte): somar de volta movimento que a projeção
  -- ainda não descontou inflaria o bônus.
  select date_trunc('month', f.data_caixa)::date as mes,
    round(sum(f.valor), 2) as valor
  from public.fato_financeiro f
  cross join corte ct
  join public.categoria_dre cd on cd.categoria = f.categoria
  where cd.neutra_bonificacao
    and f.data_caixa <= ct.dia
  group by 1
)
select c.mes,
  c.ano_mes,
  c.saldo_fim,
  c.saldo_anterior,
  round(c.saldo_fim_liquido - c.saldo_anterior_liquido, 2) as variacao_caixa,
  coalesce(n.valor, 0::numeric) as ajuste_nao_operacional,
  round(c.saldo_fim_liquido - c.saldo_anterior_liquido
        - coalesce(n.valor, 0::numeric), 2) as base_bonificacao,
  c.especie_fim,
  c.saldo_fim_liquido,
  c.saldo_anterior_liquido
from comparacao c
left join neutro n on n.mes = c.mes;

revoke all privileges on public.bonificacao_base_mes from public, anon, authenticated;

comment on view public.bonificacao_base_mes is
  'Base da bonificação do gerente. variacao_caixa exclui a espécie ainda não depositada nos dois lados da subtração (incentivo a depositar antes de fechar o mês); base_bonificacao soma de volta as categorias marcadas com categoria_dre.neutra_bonificacao. Não expor na API -- ler pela view app_gerente_saldo_variacao.';

-- Confere os objetos efetivos, não apenas o texto desta migration.
do $validacao$
declare
  v_base text := pg_get_viewdef('public.bonificacao_base_mes'::regclass, true);
  v_mes date := date_trunc('month', (select dia from public.corte_caixa))::date;
  v_marcadas text;
  v_row record;
  v_futuro numeric;
begin
  if position('neutra_bonificacao' in v_base) = 0 then
    raise exception 'A base do bônus não passou a ler a flag por categoria.';
  end if;

  -- O grupo inteiro não pode mais ser neutralizado em bloco.
  if position('NÃO OPERACIONAL' in v_base) > 0 then
    raise exception 'A base do bônus ainda neutraliza o grupo NÃO OPERACIONAL inteiro.';
  end if;

  -- A exclusão da espécie tem de continuar valendo.
  if position('venda_especie' in v_base) = 0 then
    raise exception 'A base do bônus perdeu a exclusão da espécie não depositada.';
  end if;

  select string_agg(categoria, ', ' order by categoria) into v_marcadas
  from public.categoria_dre where neutra_bonificacao;

  if v_marcadas is distinct from 'Distribuição de Lucros' then
    raise exception 'Categorias neutras inesperadas: %', coalesce(v_marcadas, '(nenhuma)');
  end if;

  select * into v_row from public.bonificacao_base_mes where mes = v_mes;

  if v_row.mes is null then
    raise exception 'A base do bônus não devolveu o mês corrente.';
  end if;

  if abs(v_row.base_bonificacao
         - (v_row.variacao_caixa - v_row.ajuste_nao_operacional)) > 0.01 then
    raise exception 'A base do bônus não fecha com a variação menos o ajuste.';
  end if;

  -- Avisa sobre movimento não operacional que ainda vai entrar na conta.
  select round(coalesce(sum(f.valor), 0), 2) into v_futuro
  from public.fato_financeiro f
  left join public.categoria_dre cd on cd.categoria = f.categoria
  where f.dre_grupo = 'NÃO OPERACIONAL'
    and not coalesce(cd.neutra_bonificacao, false)
    and f.data_caixa > (select dia from public.corte_caixa)
    and f.data_caixa < (v_mes + interval '1 month')::date;

  if v_futuro <> 0 then
    raise notice
      'Atenção: R$ % não operacional NÃO neutralizado entra na base quando o corte avançar.',
      v_futuro;
  end if;

  raise notice 'Base de %: variação R$ %, ajuste R$ %, base R$ %.',
    v_row.ano_mes, v_row.variacao_caixa, v_row.ajuste_nao_operacional,
    v_row.base_bonificacao;
end;
$validacao$;

commit;
