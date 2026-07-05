-- Calendario financeiro diario.
-- Consolida em uma RPC mensal as mesmas fontes usadas pelos paineis de
-- faturamento, caixa, despesas e contas recorrentes, sem expor tabelas brutas.

begin;

create or replace function public.listar_calendario_financeiro(p_mes date)
returns table (
  dia date,
  dia_semana smallint,
  modo text,
  meta_dia numeric,
  meta_acumulada numeric,
  faturamento_dia numeric,
  faturamento_acumulado numeric,
  venda_credito numeric,
  venda_debito numeric,
  venda_pix numeric,
  venda_extras numeric,
  venda_dinheiro numeric,
  recebimento_total numeric,
  recebimento_credito numeric,
  recebimento_debito numeric,
  recebimento_pix numeric,
  recebimento_projetado numeric,
  despesa_total numeric,
  despesa_recorrente numeric,
  despesa_nao_recorrente numeric,
  despesa_recorrente_registrada numeric,
  despesa_recorrente_nao_conciliada numeric,
  saldo_caixa numeric
)
language plpgsql
stable
security definer
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
    from generate_series(
      p_mes::timestamp,
      (p_mes + interval '1 month - 1 day')::timestamp,
      interval '1 day'
    ) gs
  ),
  cortes as (
    select
      (select cv.dia from public.corte_venda cv) as venda,
      (select cc.dia from public.corte_caixa cc) as caixa
  ),
  cancelamentos as (
    select r.stone_id, sum(abs(r.valor_bruto)) as valor
    from public.raw_stone_recebiveis r
    where r.categoria ilike '%cancelamento%'
    group by r.stone_id
  ),
  vendas_stone as (
    select
      v.data_venda::date as dia,
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
  ),
  vendas_dinheiro as (
    select v.data as dia, sum(v.valor) as dinheiro
    from public.venda_especie v
    where v.data >= p_mes and v.data < p_mes + interval '1 month'
    group by v.data
  ),
  metas as (
    select p.dia, p.meta_dia
    from public.painel_diario p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ),
  vendas_total as (
    select p.dia, p.venda, p.tipo
    from public.projecao_venda_diaria p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ),
  recebiveis as (
    select
      r.data_vencimento as dia,
      sum(case when public.unaccent(lower(r.produto)) like 'credito%'
        then r.valor_liquido else 0 end) as credito,
      sum(case when public.unaccent(lower(r.produto)) like 'debito%'
        then r.valor_liquido else 0 end) as debito
    from public.raw_stone_recebiveis r
    where r.data_vencimento >= p_mes
      and r.data_vencimento < p_mes + interval '1 month'
    group by r.data_vencimento
  ),
  pix_recebido as (
    select e.data_hora::date as dia, sum(e.valor) as valor
    from public.raw_stone_extrato e
    where e.movimentacao = 'Crédito'
      and e.tipo = 'Pix'
      and e.data_hora::date >= p_mes
      and e.data_hora::date < p_mes + interval '1 month'
    group by e.data_hora::date
  ),
  recebimentos_projetados as (
    select r.dia, sum(r.valor) as valor
    from public.recebimento_projetado r
    where r.dia >= p_mes and r.dia < p_mes + interval '1 month'
    group by r.dia
  ),
  despesas_reais as (
    select f.data_caixa as dia, sum(abs(f.valor)) as total
    from public.fato_financeiro f
    where f.data_caixa >= p_mes
      and f.data_caixa < p_mes + interval '1 month'
      and f.movimentacao = 'Débito'
      and f.entra_dre
      and f.empresa = any(array['PRAIA', 'BB']::text[])
    group by f.data_caixa
  ),
  recorrentes_reais as (
    select p.data_pagamento as dia, sum(p.valor) as total
    from public.conta_recorrente_pagamento p
    join public.conta_recorrente c on c.id = p.conta_id
    where p.data_pagamento >= p_mes
      and p.data_pagamento < p_mes + interval '1 month'
      and p.situacao = 'pago'
      and c.tipo = 'despesa'
      and c.incluir_totais
    group by p.data_pagamento
  ),
  despesas_fixas_projetadas as (
    select p.dia, sum(p.valor) as total
    from public.projecao_despesa_fixa p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
    group by p.dia
  ),
  despesas_diretas_projetadas as (
    select p.dia, sum(p.valor) as total
    from public.projecao_despesa_direta p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
    group by p.dia
  ),
  saldos as (
    select p.dia, p.saldo
    from public.painel_fluxo_caixa p
    where p.dia >= p_mes and p.dia < p_mes + interval '1 month'
  ),
  base as (
    select
      d.dia,
      extract(isodow from d.dia)::smallint as dia_semana,
      case
        when d.dia <= least(coalesce(ct.venda, d.dia), coalesce(ct.caixa, d.dia)) then 'real'
        when d.dia > greatest(coalesce(ct.venda, d.dia - 1), coalesce(ct.caixa, d.dia - 1)) then 'projetado'
        else 'parcial'
      end as modo,
      m.meta_dia,
      vt.venda as faturamento_dia,
      case when vt.tipo = 'real' then vs.credito end as venda_credito,
      case when vt.tipo = 'real' then vs.debito end as venda_debito,
      case when vt.tipo = 'real' then vs.pix end as venda_pix,
      case when vt.tipo = 'real' then vs.extras end as venda_extras,
      case when vt.tipo = 'real' then vd.dinheiro end as venda_dinheiro,
      coalesce(r.credito, 0) as recebimento_credito,
      coalesce(r.debito, 0) as recebimento_debito,
      coalesce(pr.valor, 0) as recebimento_pix,
      coalesce(rp.valor, 0) as recebimento_projetado,
      case
        when d.dia <= ct.caixa then coalesce(dr.total, 0)
        else coalesce(dfp.total, 0) + coalesce(ddp.total, 0)
      end as despesa_total,
      case
        when d.dia <= ct.caixa then least(coalesce(rr.total, 0), coalesce(dr.total, 0))
        else coalesce(dfp.total, 0)
      end as despesa_recorrente,
      case
        when d.dia <= ct.caixa then greatest(coalesce(dr.total, 0) - coalesce(rr.total, 0), 0)
        else coalesce(ddp.total, 0)
      end as despesa_nao_recorrente,
      coalesce(rr.total, 0) as despesa_recorrente_registrada,
      case when d.dia <= ct.caixa
        then greatest(coalesce(rr.total, 0) - coalesce(dr.total, 0), 0)
        else 0
      end as despesa_recorrente_nao_conciliada,
      s.saldo as saldo_caixa
    from dias d
    cross join cortes ct
    left join metas m on m.dia = d.dia
    left join vendas_total vt on vt.dia = d.dia
    left join vendas_stone vs on vs.dia = d.dia
    left join vendas_dinheiro vd on vd.dia = d.dia
    left join recebiveis r on r.dia = d.dia
    left join pix_recebido pr on pr.dia = d.dia
    left join recebimentos_projetados rp on rp.dia = d.dia
    left join despesas_reais dr on dr.dia = d.dia
    left join recorrentes_reais rr on rr.dia = d.dia
    left join despesas_fixas_projetadas dfp on dfp.dia = d.dia
    left join despesas_diretas_projetadas ddp on ddp.dia = d.dia
    left join saldos s on s.dia = d.dia
  )
  select
    b.dia,
    b.dia_semana,
    b.modo,
    round(b.meta_dia, 2),
    case when max(b.meta_dia) over () is null then null
      else round(sum(coalesce(b.meta_dia, 0)) over (order by b.dia), 2) end,
    round(b.faturamento_dia, 2),
    case when max(b.faturamento_dia) over () is null then null
      else round(sum(coalesce(b.faturamento_dia, 0)) over (order by b.dia), 2) end,
    round(b.venda_credito, 2),
    round(b.venda_debito, 2),
    round(b.venda_pix, 2),
    round(b.venda_extras, 2),
    round(b.venda_dinheiro, 2),
    round(b.recebimento_credito + b.recebimento_debito + b.recebimento_pix + b.recebimento_projetado, 2),
    round(b.recebimento_credito, 2),
    round(b.recebimento_debito, 2),
    round(b.recebimento_pix, 2),
    round(b.recebimento_projetado, 2),
    round(b.despesa_total, 2),
    round(b.despesa_recorrente, 2),
    round(b.despesa_nao_recorrente, 2),
    round(b.despesa_recorrente_registrada, 2),
    round(b.despesa_recorrente_nao_conciliada, 2),
    round(b.saldo_caixa, 2)
  from base b
  order by b.dia;
end;
$function$;

comment on function public.listar_calendario_financeiro(date) is
  'Resumo financeiro diario mensal, com realizado, projecoes e detalhamento compacto por canal.';

revoke all privileges on function public.listar_calendario_financeiro(date)
  from public, anon, authenticated;
grant execute on function public.listar_calendario_financeiro(date) to authenticated;

insert into public.pagina_permissao (pagina, papeis)
values ('calendario.html', array['socio'])
on conflict (pagina) do nothing;

commit;
