-- =====================================================================
-- Calendario realizado usa as mesmas movimentacoes do saldo de caixa
-- =====================================================================
--
-- PROBLEMA
--   O saldo realizado vem do fluxo integral de caixa, mas as colunas de
--   recebimentos e despesas usavam recortes operacionais diferentes:
--   agenda de recebiveis, tipo Pix no extrato e apenas debitos que entram na
--   DRE. Assim, movimentos que alteram Stone/BB ficavam invisiveis.
--
--   Na Stone, venda Pix por QR Code chega ao extrato como tipo "Transacao".
--   Tipo "Pix" representa transferencia fora da venda QR Code.
--
-- SOLUCAO
--   Nos dias ate corte_caixa, entradas e saidas passam a usar exatamente o
--   universo de caixa_real_diario: fato_financeiro das empresas PRAIA/BB,
--   excluindo origem bs_cash. Os creditos sao separados em:
--     - recebimento_credito: Recebivel de Cartao liquidado;
--     - recebimento_pix: Transacao (venda QR Code);
--     - recebimento_projetado: outras entradas/transferencias no realizado.
--   O nome legado das colunas e preservado para nao quebrar a RPC. Depois do
--   corte, continuam valendo recebiveis conhecidos e projecoes existentes.
--
--   listar_despesas_dia recebe o mesmo recorte integral dos debitos, para o
--   detalhe somar exatamente a coluna Despesas.
--
-- OBJETOS
--   ~ public.listar_calendario_financeiro(date)
--   ~ public.listar_despesas_dia(date)
--
-- RISCO
--   Dias realizados podem exibir totais brutos maiores quando ha
--   transferencias, pois entrada e saida ficam visiveis. O efeito liquido e
--   preservado. Nenhuma tabela, classificacao, DRE ou projecao e alterada.
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
  with dias as (
    select gs::date as dia
    from generate_series(p_mes::timestamp,
      (p_mes + interval '1 month - 1 day')::timestamp, interval '1 day') gs
  ), cortes as (
    select (select cv.dia from public.corte_venda cv) as venda,
           (select cc.dia from public.corte_caixa cc) as caixa
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
    where r.data_vencimento >= p_mes
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
    where r.dia >= p_mes and r.dia < p_mes + interval '1 month' group by r.dia
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
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month' group by p.dia
  ), despesas_diretas_projetadas as (
    select p.dia, sum(p.valor) as total from public.projecao_despesa_direta p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month' group by p.dia
  ), saldos as (
    select p.dia, p.saldo from public.painel_fluxo_caixa p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
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
      case when d.dia <= ct.caixa then coalesce(er.outras, 0)
           else coalesce(rp.valor, 0) end as recebimento_projetado,
      case when d.dia <= ct.caixa then coalesce(er.total, 0)
           else coalesce(r.credito, 0) + coalesce(r.debito, 0) + coalesce(rp.valor, 0)
      end as recebimento_total,
      case when d.dia <= ct.caixa then coalesce(sr.total, 0)
           else coalesce(dfp.total, 0) + coalesce(ddp.total, 0) end as despesa_total,
      case when d.dia <= ct.caixa then least(coalesce(rr.total, 0), coalesce(sr.total, 0))
           else coalesce(dfp.total, 0) end as despesa_recorrente,
      case when d.dia <= ct.caixa then greatest(coalesce(sr.total, 0) - coalesce(rr.total, 0), 0)
           else coalesce(ddp.total, 0) end as despesa_nao_recorrente,
      coalesce(rr.total, 0) as despesa_recorrente_registrada,
      case when d.dia <= ct.caixa then greatest(coalesce(rr.total, 0) - coalesce(sr.total, 0), 0)
           else 0 end as despesa_recorrente_nao_conciliada,
      s.saldo as saldo_real
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
  ), calculado as (
    select b.*, coalesce((select p.saldo from public.painel_fluxo_caixa p
          where p.dia <= b.corte_caixa order by p.dia desc limit 1), 0::numeric)
      + sum(case when b.dia > b.corte_caixa
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
  'Calendario financeiro: realizado usa o fluxo integral que movimenta o saldo; futuro usa as projecoes vigentes.';

revoke all privileges on function public.listar_calendario_financeiro(date) from public, anon;
grant execute on function public.listar_calendario_financeiro(date) to authenticated;

create or replace function public.listar_despesas_dia(p_dia date)
returns table (descricao text, categoria text, valor numeric)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_dia is null then
    raise exception using errcode = '22023', message = 'Dia invalido.';
  end if;

  return query
  select
    coalesce(nullif(btrim(f.fornecedor), ''),
      nullif(btrim(f.contraparte_nome), ''), f.categoria, f.tipo,
      'Sem descricao') as descricao,
    coalesce(f.categoria, f.tipo, 'Movimentacao de caixa') as categoria,
    round(abs(f.valor), 2) as valor
  from public.fato_financeiro f
  where f.data_caixa = p_dia
    and f.movimentacao = 'Débito'
    and f.empresa = any(array['PRAIA', 'BB']::text[])
    and f.origem is distinct from 'bs_cash'
  order by abs(f.valor) desc, 1;
end;
$function$;

comment on function public.listar_despesas_dia(date) is
  'Todas as saidas que compoem o fluxo realizado do Calendario, no mesmo universo do saldo.';

revoke all privileges on function public.listar_despesas_dia(date)
  from public, anon, authenticated;
grant execute on function public.listar_despesas_dia(date) to authenticated;

commit;
