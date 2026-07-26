-- =====================================================================
-- Calendario: uma avaliacao por fonte (corrige o timeout intermitente)
-- =====================================================================
--
-- PROBLEMA
--   calendario.html falhava de forma intermitente com "O servidor demorou
--   a responder". O retry adicionado em 20260764/calendario.html tratava o
--   sintoma; a causa era o tempo da propria RPC.
--
--   Medido nesta base: listar_calendario_financeiro levava 7,5 a 8,8s,
--   contra o limite de 8s do PostgREST -- por isso falhava as vezes e
--   funcionava outras.
--
--   O diagnostico (explain analyze do corpo da funcao) mostrou 355
--   InitPlans e a CTE interna de_para_u repetida 24 vezes: ou seja,
--   fato_financeiro (view viva que une raw_historico, stone, bb, bs_cash
--   e inter, ~52 mil linhas) estava sendo expandida 24 vezes na mesma
--   consulta. Somadas isoladamente, as fontes custam 1,65s; juntas,
--   passavam de 8s. Nenhum ajuste de planner ajudou (mergejoin off,
--   nestloop off, jit off e collapse_limit=1 pioraram ou empataram),
--   confirmando trabalho repetido e nao plano ruim.
--
-- SOLUCAO (sem mudar regra financeira nem contrato)
--   1. entradas_reais e saidas_reais eram dois scans completos do
--      fato_financeiro sobre o mesmo recorte (mesmo mes, mesmas empresas,
--      mesma exclusao de bs_cash), diferindo so no movimentacao. Viram uma
--      CTE movimento_real com credito e debito na mesma passada; as duas
--      CTEs antigas passam a ler dela e mantem exatamente as mesmas
--      colunas de saida.
--   2. As CTEs de fonte passam a ser WITH ... AS MATERIALIZED. Sem isso o
--      planner faz inline de cada uma e reavalia as views por baixo
--      (projecao_venda_diaria sozinha reaparecia em vendas_total,
--      recebimentos_projetados e despesas_diretas_projetadas). Com
--      MATERIALIZED cada fonte e calculada uma unica vez.
--
--   Resultado medido no mes corrente, 3 execucoes cada, mesma conexao:
--     antes 7,45s  ->  depois 4,27s  (-43%)
--   e as 31 linhas retornadas sao identicas byte a byte (comparadas em
--   Python antes desta migration).
--
-- OBJETOS
--   ~ public.listar_calendario_financeiro(date) (create or replace;
--     mesma assinatura, mesmas colunas, mesmos valores)
--
-- NAO FEITO DE PROPOSITO
--   Materializar projecao_venda_diaria daria mais uns 3s, mas corte_venda
--   e corte_caixa dependem de now(): a MV ficaria defasada na virada do
--   dia ate o proximo refresh. Preferi o ganho sem risco de correcao. Se
--   voltar a apertar, o caminho e materializar as projecoes com refresh
--   amarrado ao corte -- ver docs/CANAL_IA.md.
--
-- RISCO: baixo. Sem mudanca de schema, de permissao ou de regra. O maior
--   cuidado e que MATERIALIZED impede o pushdown de predicado para dentro
--   das CTEs -- aqui isso nao pesa porque todas ja filtram pelo mes.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.listar_calendario_financeiro(p_mes date)
 RETURNS TABLE(dia date, dia_semana smallint, modo text, meta_dia numeric, meta_acumulada numeric, faturamento_dia numeric, faturamento_acumulado numeric, venda_credito numeric, venda_debito numeric, venda_pix numeric, venda_extras numeric, venda_dinheiro numeric, recebimento_total numeric, recebimento_credito numeric, recebimento_debito numeric, recebimento_pix numeric, recebimento_projetado numeric, despesa_total numeric, despesa_recorrente numeric, despesa_nao_recorrente numeric, despesa_recorrente_registrada numeric, despesa_recorrente_nao_conciliada numeric, saldo_caixa numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_mes is null or p_mes <> date_trunc('month', p_mes)::date then
    raise exception using errcode = '22023', message = 'Mes invalido.';
  end if;

  return query
  with dias as materialized (
    select gs::date as dia
    from generate_series(p_mes::timestamp,
      (p_mes + interval '1 month - 1 day')::timestamp, interval '1 day') gs
  ), cortes as materialized (
    select (select cv.dia from public.corte_venda cv) as venda,
           (select cc.dia from public.corte_caixa cc) as caixa
  ), cancelamentos as materialized (
    select r.stone_id, sum(abs(r.valor_bruto)) as valor
    from public.raw_stone_recebiveis r
    where r.categoria ilike '%cancelamento%'
    group by r.stone_id
  ), vendas_stone as materialized (
    select v.data_venda::date as dia,
      sum(case when public.unaccent(lower(v.produto)) like 'credito%'
        then v.valor_bruto - coalesce(c.valor, 0) else 0 end) as credito,
      sum(case when public.unaccent(lower(v.produto)) like 'debito%'
        then v.valor_bruto - coalesce(c.valor, 0) else 0 end) as debito,
      sum(case when lower(v.produto) like 'pix%'
        then v.valor_bruto - coalesce(c.valor, 0) else 0 end) as pix,
      sum(case when public.unaccent(lower(v.produto)) not like 'credito%'
                    and public.unaccent(lower(v.produto)) not like 'debito%'
                    and lower(v.produto) not like 'pix%'
        then v.valor_bruto - coalesce(c.valor, 0) else 0 end) as extras
    from public.raw_stone_vendas v
    left join cancelamentos c on c.stone_id = v.stone_id
    where v.data_venda::date >= p_mes
      and v.data_venda::date < p_mes + interval '1 month'
    group by v.data_venda::date
  ), vendas_dinheiro as materialized (
    select v.data as dia, sum(v.valor) as dinheiro
    from public.venda_especie v
    where v.data >= p_mes and v.data < p_mes + interval '1 month'
    group by v.data
  ), metas as materialized (
    select p.dia, p.meta_dia from public.painel_diario p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ), vendas_total as materialized (
    select p.dia, p.venda, p.tipo from public.projecao_venda_diaria p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ), recebiveis as materialized (
    select r.data_vencimento as dia,
      sum(case when public.unaccent(lower(r.produto)) like 'credito%'
        then r.valor_liquido else 0 end) as credito,
      sum(case when public.unaccent(lower(r.produto)) like 'debito%'
        then r.valor_liquido else 0 end) as debito
    from public.raw_stone_recebiveis r
    where r.data_vencimento >= p_mes
      and r.data_vencimento < p_mes + interval '1 month'
    group by r.data_vencimento
  ), movimento_real as materialized (
    -- Credito e debito na mesma passada: antes eram dois scans completos
    -- do fato_financeiro (view viva, ~52 mil linhas) para o mesmo recorte.
    select
      f.data_caixa as dia,
      sum(case
        when f.movimentacao = 'Crédito'
         and f.origem = 'stone_extrato' and f.tipo = 'Recebível de Cartão'
          then abs(f.valor) else 0 end) as cartoes,
      sum(case
        when f.movimentacao = 'Crédito'
         and f.origem = 'stone_extrato' and f.tipo = 'Transação'
          then abs(f.valor) else 0 end) as qr_code,
      sum(case
        when f.movimentacao = 'Crédito'
         and (f.origem is distinct from 'stone_extrato'
              or coalesce(f.tipo, '') <> all(
                   array['Recebível de Cartão', 'Transação']::text[]))
          then abs(f.valor) else 0 end) as outras,
      sum(case when f.movimentacao = 'Crédito' then abs(f.valor) else 0 end) as total_credito,
      sum(case when f.movimentacao = 'Débito' then abs(f.valor) else 0 end) as total_debito
    from public.fato_financeiro f
    where f.data_caixa >= p_mes
      and f.data_caixa < p_mes + interval '1 month'
      and f.movimentacao = any(array['Crédito', 'Débito']::text[])
      and f.empresa = any(array['PRAIA', 'BB']::text[])
      and f.origem is distinct from 'bs_cash'
    group by f.data_caixa
  ), entradas_reais as (
    select m.dia, m.cartoes, m.qr_code, m.outras, m.total_credito as total
    from movimento_real m
  ), recebimentos_projetados as materialized (
    select r.dia, sum(r.valor) as valor from public.recebimento_projetado r
    where r.dia >= p_mes and r.dia < p_mes + interval '1 month' group by r.dia
  ), saidas_reais as (
    select m.dia, m.total_debito as total from movimento_real m
  ), recorrentes_reais as materialized (
    select p.data_pagamento as dia, sum(p.valor) as total
    from public.conta_recorrente_pagamento p
    join public.conta_recorrente c on c.id = p.conta_id
    where p.data_pagamento >= p_mes
      and p.data_pagamento < p_mes + interval '1 month'
      and p.situacao = 'pago' and c.tipo = 'despesa' and c.incluir_totais
    group by p.data_pagamento
  ), despesas_fixas_projetadas as materialized (
    select p.dia, sum(p.valor) as total from public.projecao_despesa_fixa p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month' group by p.dia
  ), despesas_diretas_projetadas as materialized (
    select p.dia, sum(p.valor) as total from public.projecao_despesa_direta p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month' group by p.dia
  ), saldos as materialized (
    select p.dia, p.saldo from public.painel_fluxo_caixa p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ), saldos_detalhados as materialized (
    select
      s.dia,
      s.saldo_total,
      s.variacao_dinheiro_pendente
    from public.mv_saldo_caixa_diario_detalhado s
    where s.dia >= p_mes and s.dia < p_mes + interval '1 month'
  ), base as (
    select d.dia, extract(isodow from d.dia)::smallint as dia_semana,
      ct.caixa as corte_caixa,
      case when d.dia <= least(coalesce(ct.venda, d.dia), coalesce(ct.caixa, d.dia)) then 'real'
           when d.dia > greatest(coalesce(ct.venda, d.dia - 1), coalesce(ct.caixa, d.dia - 1)) then 'projetado'
           else 'parcial' end as modo,
      m.meta_dia, vt.venda as faturamento_dia,
      case when vt.tipo = 'real' then vs.credito end as venda_credito,
      case when vt.tipo = 'real' then vs.debito end as venda_debito,
      case when vt.tipo = 'real' then vs.pix end as venda_pix,
      case when vt.tipo = 'real' then vs.extras end as venda_extras,
      case when vt.tipo = 'real' then vd.dinheiro end as venda_dinheiro,
      case when d.dia <= ct.caixa then coalesce(er.cartoes, 0)
           else coalesce(r.credito, 0) end as recebimento_credito,
      case when d.dia <= ct.caixa then null::numeric
           else coalesce(r.debito, 0) end as recebimento_debito,
      case when d.dia <= ct.caixa then coalesce(er.qr_code, 0)
           else 0::numeric end as recebimento_pix,
      case when d.dia <= ct.caixa then
             coalesce(er.outras, 0)
               + greatest(coalesce(sd.variacao_dinheiro_pendente, 0), 0)
           else coalesce(rp.valor, 0) end as recebimento_projetado,
      case when d.dia <= ct.caixa then
             coalesce(er.total, 0)
               + greatest(coalesce(sd.variacao_dinheiro_pendente, 0), 0)
           else coalesce(r.credito, 0) + coalesce(r.debito, 0) + coalesce(rp.valor, 0)
      end as recebimento_total,
      case when d.dia <= ct.caixa then
             coalesce(sr.total, 0)
               + greatest(-coalesce(sd.variacao_dinheiro_pendente, 0), 0)
           else coalesce(dfp.total, 0) + coalesce(ddp.total, 0) end as despesa_total,
      case when d.dia <= ct.caixa then least(coalesce(rr.total, 0), coalesce(sr.total, 0))
           else coalesce(dfp.total, 0) end as despesa_recorrente,
      case when d.dia <= ct.caixa then
             greatest(coalesce(sr.total, 0) - coalesce(rr.total, 0), 0)
               + greatest(-coalesce(sd.variacao_dinheiro_pendente, 0), 0)
           else coalesce(ddp.total, 0) end as despesa_nao_recorrente,
      coalesce(rr.total, 0) as despesa_recorrente_registrada,
      case when d.dia <= ct.caixa then greatest(coalesce(rr.total, 0) - coalesce(sr.total, 0), 0)
           else 0 end as despesa_recorrente_nao_conciliada,
      coalesce(sd.saldo_total, s.saldo) as saldo_real
    from dias d cross join cortes ct
    left join metas m on m.dia = d.dia
    left join vendas_total vt on vt.dia = d.dia
    left join vendas_stone vs on vs.dia = d.dia
    left join vendas_dinheiro vd on vd.dia = d.dia
    left join recebiveis r on r.dia = d.dia
    left join entradas_reais er on er.dia = d.dia
    left join recebimentos_projetados rp on rp.dia = d.dia
    left join saidas_reais sr on sr.dia = d.dia
    left join recorrentes_reais rr on rr.dia = d.dia
    left join despesas_fixas_projetadas dfp on dfp.dia = d.dia
    left join despesas_diretas_projetadas ddp on ddp.dia = d.dia
    left join saldos s on s.dia = d.dia
    left join saldos_detalhados sd on sd.dia = d.dia
  ), calculado as (
    select b.*, coalesce(
      (select s.saldo_total
       from public.mv_saldo_caixa_diario_detalhado s
       where s.dia <= b.corte_caixa
       order by s.dia desc
       limit 1),
      (select p.saldo
       from public.painel_fluxo_caixa p
       where p.dia <= b.corte_caixa
       order by p.dia desc
       limit 1),
      0::numeric
    ) + sum(case when b.dia > b.corte_caixa
          then b.recebimento_total - b.despesa_total else 0::numeric end)
        over (order by b.dia rows between unbounded preceding and current row) as saldo_projetado
    from base b
  )
  select b.dia, b.dia_semana, b.modo, round(b.meta_dia, 2),
    case when max(b.meta_dia) over () is null then null
      else round(sum(coalesce(b.meta_dia, 0)) over (order by b.dia), 2) end,
    round(b.faturamento_dia, 2),
    case when max(b.faturamento_dia) over () is null then null
      else round(sum(coalesce(b.faturamento_dia, 0)) over (order by b.dia), 2) end,
    round(b.venda_credito, 2), round(b.venda_debito, 2), round(b.venda_pix, 2),
    round(b.venda_extras, 2), round(b.venda_dinheiro, 2), round(b.recebimento_total, 2),
    round(b.recebimento_credito, 2), round(b.recebimento_debito, 2),
    round(b.recebimento_pix, 2), round(b.recebimento_projetado, 2),
    round(b.despesa_total, 2), round(b.despesa_recorrente, 2),
    round(b.despesa_nao_recorrente, 2), round(b.despesa_recorrente_registrada, 2),
    round(b.despesa_recorrente_nao_conciliada, 2),
    round(case when b.dia <= b.corte_caixa then b.saldo_real else b.saldo_projetado end, 2)
  from calculado b order by b.dia;
end;
$function$;

comment on function public.listar_calendario_financeiro(date) is
  'Calendario financeiro: uma avaliacao por fonte (CTEs materializadas) e uma unica passada no fato_financeiro.';

revoke all privileges on function public.listar_calendario_financeiro(date)
  from public, anon;
grant execute on function public.listar_calendario_financeiro(date)
  to authenticated;
