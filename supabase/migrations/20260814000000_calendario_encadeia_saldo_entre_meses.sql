-- =====================================================================
-- Calendario: o dia 1o herda o saldo do ultimo dia do mes anterior
-- =====================================================================
--
-- PROBLEMA
--   Agosto/2026 projetava fechar com R$ 175.386 e setembro/2026 abria com
--   R$ 131.755 -- um buraco de R$ 43.631 entre o fechamento de um mes e a
--   abertura do seguinte.
--
--   Em listar_calendario_financeiro (20260763000000) o saldo projetado e:
--
--     <ultimo saldo real ate o corte_caixa>
--     + sum(recebimento_total - despesa_total) over (order by dia)
--     from base
--
--   A ancora e sempre o ultimo saldo realizado (hoje 10/08/2026 =
--   R$ 131.754,98), mas a CTE `base` so contem os dias do mes consultado.
--   Resultado: agosto acumula 11/08..31/08 em cima da ancora, e setembro
--   volta para a mesma ancora e acumula so 01/09..30/09 -- os 21 dias
--   projetados de agosto somem. Conferido: 175.386 - 43.631 = 131.755,
--   exatamente a ancora.
--
--   E o erro cresce: todo mes futuro reabria na mesma ancora de 10/08,
--   entao outubro ignorava agosto E setembro.
--
--   A prova de conciliacao da tela ("diferenca R$ 0,00") nao pegava isso
--   porque ela so confere abertura + recebimentos - despesas dentro do
--   mes, e a abertura e derivada do proprio dia 1o (calendario.html).
--   Nunca compara o fechamento de um mes com a abertura do seguinte.
--
-- SOLUCAO
--   Nao muda nenhuma regra de projecao -- so o alcance do acumulador. A
--   lista de dias passa a comecar em least(p_mes, corte_caixa + 1), a soma
--   corrente roda sobre essa janela inteira, e o mes pedido e recortado no
--   SELECT final. Assim o dia 1o de setembro ja chega carregando o liquido
--   projetado de agosto, que e o mesmo numero que a tela de agosto mostra.
--
--   O recorte no SELECT final e proposital: em SQL o WHERE roda antes das
--   window functions do mesmo nivel, entao meta_acumulada e
--   faturamento_acumulado continuam acumulando so dentro do mes, enquanto
--   saldo_projetado (calculado na CTE anterior) ja vem encadeado.
--
--   As CTEs de dados realizados (entradas_reais, saidas_reais,
--   vendas_stone, vendas_dinheiro, recorrentes_reais, saldos) continuam
--   filtradas pelo mes: os dias extras da janela sao todos posteriores ao
--   corte_caixa e usam apenas o ramo projetado. Isso mantem o custo da
--   consulta praticamente igual -- so as quatro tabelas de projecao
--   (recebiveis, recebimento_projetado, projecao_despesa_fixa,
--   projecao_despesa_direta) leem alguns dias a mais.
--
-- OBJETO
--   ~ public.listar_calendario_financeiro(date)  -- mesma assinatura,
--     mesmas colunas e tipos
--
-- RISCO: baixo.
--   - Mes passado ou mes corrente: least(p_mes, corte+1) = p_mes, a janela
--     fica identica a de hoje e nenhum numero muda.
--   - So meses inteiramente futuros mudam, e mudam para o valor correto:
--     validado por leitura que a abertura de setembro passa de
--     131.754,98 para 175.385,55, igual ao fechamento de agosto.
--   - Nenhuma tabela e alterada; a funcao e stable/security definer como
--     antes e as permissoes sao reaplicadas iguais.
-- =====================================================================

begin;

create or replace function public.listar_calendario_financeiro(p_mes date)
returns table (
  dia date, dia_semana smallint, modo text, meta_dia numeric,
  meta_acumulada numeric, faturamento_dia numeric,
  faturamento_acumulado numeric, venda_credito numeric, venda_debito numeric,
  venda_pix numeric, venda_extras numeric, venda_dinheiro numeric,
  recebimento_total numeric, recebimento_credito numeric,
  recebimento_debito numeric, recebimento_pix numeric,
  recebimento_projetado numeric, despesa_total numeric,
  despesa_recorrente numeric, despesa_nao_recorrente numeric,
  despesa_recorrente_registrada numeric,
  despesa_recorrente_nao_conciliada numeric, saldo_caixa numeric
)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_mes is null or p_mes <> date_trunc('month', p_mes)::date then
    raise exception using errcode = '22023', message = 'Mes invalido.';
  end if;

  return query
  with cortes as (
    select (select cv.dia from public.corte_venda cv) as venda,
           (select cc.dia from public.corte_caixa cc) as caixa
  ), janela as (
    -- Comeca no dia seguinte ao corte quando o mes pedido e futuro, para o
    -- acumulado do saldo atravessar os meses intermediarios.
    select least(p_mes, coalesce(ct.caixa, p_mes) + 1) as inicio,
           (p_mes + interval '1 month - 1 day')::date as fim
    from cortes ct
  ), dias as (
    select gs::date as dia
    from janela j,
      generate_series(j.inicio::timestamp, j.fim::timestamp, interval '1 day') gs
  ), cancelamentos as (
    select r.stone_id, sum(abs(r.valor_bruto)) as valor
    from public.raw_stone_recebiveis r
    where r.categoria ilike '%cancelamento%'
    group by r.stone_id
  ), vendas_stone as (
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
  ), vendas_dinheiro as (
    select v.data as dia, sum(v.valor) as dinheiro
    from public.venda_especie v
    where v.data >= p_mes and v.data < p_mes + interval '1 month'
    group by v.data
  ), metas as (
    select p.dia, p.meta_dia from public.painel_diario p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ), vendas_total as (
    select p.dia, p.venda, p.tipo from public.projecao_venda_diaria p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ), recebiveis as (
    select r.data_vencimento as dia,
      sum(case when public.unaccent(lower(r.produto)) like 'credito%'
        then r.valor_liquido else 0 end) as credito,
      sum(case when public.unaccent(lower(r.produto)) like 'debito%'
        then r.valor_liquido else 0 end) as debito
    from public.raw_stone_recebiveis r
    where r.data_vencimento >= (select j.inicio from janela j)
      and r.data_vencimento < p_mes + interval '1 month'
    group by r.data_vencimento
  ), entradas_reais as (
    select
      f.data_caixa as dia,
      sum(case
        when f.origem = 'stone_extrato' and f.tipo = 'Recebível de Cartão'
          then abs(f.valor) else 0 end) as cartoes,
      sum(case
        when f.origem = 'stone_extrato' and f.tipo = 'Transação'
          then abs(f.valor) else 0 end) as qr_code,
      sum(case
        when f.origem is distinct from 'stone_extrato'
          or coalesce(f.tipo, '') <> all(
            array['Recebível de Cartão', 'Transação']::text[]
          ) then abs(f.valor) else 0 end) as outras,
      sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.data_caixa >= p_mes
      and f.data_caixa < p_mes + interval '1 month'
      and f.movimentacao = 'Crédito'
      and f.empresa = any(array['PRAIA', 'BB']::text[])
      and f.origem is distinct from 'bs_cash'
    group by f.data_caixa
  ), recebimentos_projetados as (
    select r.dia, sum(r.valor) as valor from public.recebimento_projetado r
    where r.dia >= (select j.inicio from janela j)
      and r.dia < p_mes + interval '1 month' group by r.dia
  ), saidas_reais as (
    select f.data_caixa as dia, sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.data_caixa >= p_mes
      and f.data_caixa < p_mes + interval '1 month'
      and f.movimentacao = 'Débito'
      and f.empresa = any(array['PRAIA', 'BB']::text[])
      and f.origem is distinct from 'bs_cash'
    group by f.data_caixa
  ), recorrentes_reais as (
    select p.data_pagamento as dia, sum(p.valor) as total
    from public.conta_recorrente_pagamento p
    join public.conta_recorrente c on c.id = p.conta_id
    where p.data_pagamento >= p_mes
      and p.data_pagamento < p_mes + interval '1 month'
      and p.situacao = 'pago' and c.tipo = 'despesa' and c.incluir_totais
    group by p.data_pagamento
  ), despesas_fixas_projetadas as (
    select p.dia, sum(p.valor) as total from public.projecao_despesa_fixa p
    where p.dia >= (select j.inicio from janela j)
      and p.dia < p_mes + interval '1 month' group by p.dia
  ), despesas_diretas_projetadas as (
    select p.dia, sum(p.valor) as total from public.projecao_despesa_direta p
    where p.dia >= (select j.inicio from janela j)
      and p.dia < p_mes + interval '1 month' group by p.dia
  ), saldos as (
    select p.dia, p.saldo from public.painel_fluxo_caixa p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ), saldos_detalhados as (
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
  from calculado b
  where b.dia >= p_mes
  order by b.dia;
end;
$function$;

comment on function public.listar_calendario_financeiro(date) is
  'Calendario financeiro: saldo realizado detalhado por data e projecao encadeada entre meses a partir do corte de caixa.';

revoke all privileges on function public.listar_calendario_financeiro(date)
  from public, anon;
grant execute on function public.listar_calendario_financeiro(date)
  to authenticated;

commit;
