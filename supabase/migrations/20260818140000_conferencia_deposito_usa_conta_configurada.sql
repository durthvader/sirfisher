-- Faz a conferencia de dinheiro ler a conta de deposito configurada, sem
-- pressupor que ela seja o Banco do Brasil. Nenhum dado financeiro e escrito.

begin;

create or replace view private.extrato_bancario_configuravel as
select
  'bb:' || b.id::text as id,
  b.data,
  b.valor::numeric(14, 2) as valor,
  b.lancamento as descricao,
  b.conta_id::bigint as conta_id
from public.raw_bb b
where b.data is not null

union all

select
  'inter:' || i.id::text,
  i.data,
  i.valor::numeric(14, 2),
  coalesce(i.historico, i.descricao),
  i.conta_id::bigint
from public.raw_inter i

union all

select
  'bs_cash:' || c.id::text,
  c.data_hora::date,
  c.valor::numeric(14, 2),
  coalesce(c.operacao, c.historico, c.favorecido),
  c.conta_id::bigint
from public.raw_bs_cash c

union all

select
  'stone_extrato:' || e.id::text,
  e.data_hora::date,
  e.valor::numeric(14, 2),
  coalesce(e.tipo, e.descricao),
  e.conta_id::bigint
from public.raw_stone_extrato e
where e.data_hora is not null;

comment on view private.extrato_bancario_configuravel is
  'Formato comum, privado e somente leitura dos extratos suportados pela conferencia de deposito.';

revoke all privileges on private.extrato_bancario_configuravel
from public, anon, authenticated;

-- Na primeira aplicacao, a conta vigente deve produzir exatamente o mesmo
-- conjunto que a implementacao anterior (raw_bb). Se nao produzir, a migration
-- para antes de trocar as views e exige revisao manual da configuracao.
do $validacao_compatibilidade$
declare
  v_ja_aplicada boolean;
  v_extrato_ate_antigo date;
  v_extrato_ate_novo date;
begin
  select position(
    'extrato_bancario_configuravel' in
    pg_get_viewdef('public.app_conferencia_deposito_especie'::regclass, true)
  ) > 0 into v_ja_aplicada;

  if v_ja_aplicada then
    return;
  end if;

  if exists (
    with cfg as (
      select
        c.conferencia_deposito_desde as inicio,
        c.conta_deposito_id,
        c.deposito_descricao_padrao,
        greatest(
          0,
          public.parametro_valor('deposito_janela_anterior_dias', 1)::integer
        ) as janela_anterior
      from public.configuracao_operacional c
      where c.singleton
    ), antigo as (
      select 'bb:' || b.id::text as id, b.data, b.valor::numeric(14, 2) as valor
      from public.raw_bb b
      cross join cfg
      where b.lancamento ilike cfg.deposito_descricao_padrao
        and b.data >= cfg.inicio - cfg.janela_anterior
        and (cfg.conta_deposito_id is null or b.conta_id = cfg.conta_deposito_id)
    ), novo as (
      select e.id, e.data, e.valor
      from private.extrato_bancario_configuravel e
      cross join cfg
      where e.descricao ilike cfg.deposito_descricao_padrao
        and e.data >= cfg.inicio - cfg.janela_anterior
        and (cfg.conta_deposito_id is null or e.conta_id = cfg.conta_deposito_id)
    ), diferencas as (
      (select * from antigo except all select * from novo)
      union all
      (select * from novo except all select * from antigo)
    )
    select 1 from diferencas
  ) then
    raise exception
      'A conta de deposito configurada mudaria os lancamentos conciliados; migracao cancelada.';
  end if;

  select max(b.data)
    into v_extrato_ate_antigo
  from public.raw_bb b
  cross join public.configuracao_operacional c
  where c.singleton
    and (c.conta_deposito_id is null or b.conta_id = c.conta_deposito_id);

  select max(e.data)
    into v_extrato_ate_novo
  from private.extrato_bancario_configuravel e
  cross join public.configuracao_operacional c
  where c.singleton
    and (c.conta_deposito_id is null or e.conta_id = c.conta_deposito_id);

  if v_extrato_ate_antigo is distinct from v_extrato_ate_novo then
    raise exception
      'A conta de deposito configurada mudaria a data final do extrato; migracao cancelada.';
  end if;
end;
$validacao_compatibilidade$;

create or replace view public.app_conferencia_deposito_especie
with (security_barrier = true, security_invoker = false) as
with cfg as (
  select
    c.conferencia_deposito_desde as inicio,
    c.conta_deposito_id,
    c.deposito_descricao_padrao,
    c.fuso_horario,
    public.unidade_principal_nome() as unidade,
    greatest(1, public.parametro_valor('deposito_lote_intervalo_minutos', 10)::integer) as lote_minutos,
    greatest(0, public.parametro_valor('deposito_janela_anterior_dias', 1)::integer) as janela_anterior,
    greatest(0, public.parametro_valor('deposito_janela_posterior_dias', 2)::integer) as janela_posterior,
    greatest(0, public.parametro_valor('deposito_tolerancia_valor', 0.01)) as tolerancia
  from public.configuracao_operacional c
  where c.singleton
), marcadas as (
  select v.valor, v.depositada_em, v.depositada_por,
    case
      when lag(v.depositada_em) over (order by v.depositada_em) is null then 1
      when v.depositada_em - lag(v.depositada_em) over (order by v.depositada_em)
           > make_interval(mins => cfg.lote_minutos) then 1
      else 0
    end as abre_lote
  from public.venda_especie v
  cross join cfg
  where v.unidade = cfg.unidade
    and v.depositada_em is not null
    and v.valor > 0
    and (v.depositada_em at time zone cfg.fuso_horario)::date >= cfg.inicio
), numeradas as (
  select m.*,
    sum(m.abre_lote) over (
      order by m.depositada_em rows between unbounded preceding and current row
    ) as lote
  from marcadas m
), lotes as (
  select n.lote,
    (min(n.depositada_em) at time zone cfg.fuso_horario)::date as data_lote,
    min(n.depositada_em) as marcado_em,
    count(*)::int as qtd_sangrias,
    sum(n.valor)::numeric(14, 2) as marcado,
    private.nome_exibicao_usuario(
      (array_agg(n.depositada_por order by n.depositada_em))[1]
    ) as marcado_por_nome
  from numeradas n cross join cfg
  group by n.lote, cfg.fuso_horario
), depositos as (
  select e.id, e.data, e.valor
  from private.extrato_bancario_configuravel e
  cross join cfg
  where e.descricao ilike cfg.deposito_descricao_padrao
    and e.data >= cfg.inicio - cfg.janela_anterior
    and (cfg.conta_deposito_id is null or e.conta_id = cfg.conta_deposito_id)
), deposito_do_lote as (
  select distinct on (d.id) d.id, d.data, d.valor, l.lote
  from depositos d
  cross join cfg
  left join lotes l
    on d.data between l.data_lote - cfg.janela_anterior
                  and l.data_lote + cfg.janela_posterior
  order by d.id, abs(d.data - l.data_lote) nulls last, l.data_lote
), extrato as (
  select lote, count(*)::int as qtd_lancamentos,
         sum(valor)::numeric(14, 2) as extrato
  from deposito_do_lote where lote is not null group by lote
), orfaos as (
  select d.data, count(*)::int as qtd_lancamentos,
         sum(d.valor)::numeric(14, 2) as extrato
  from deposito_do_lote d where d.lote is null group by d.data
), ajustes as (
  select a.data, sum(a.valor)::numeric(14, 2) as ajuste
  from public.conferencia_deposito_ajuste a
  where a.desfeito_em is null group by a.data
)
select
  l.data_lote as data, l.marcado_em, l.marcado_por_nome, l.qtd_sangrias,
  l.marcado, coalesce(e.extrato, 0)::numeric(14, 2) as extrato,
  coalesce(e.qtd_lancamentos, 0) as qtd_lancamentos,
  coalesce(aj.ajuste, 0)::numeric(14, 2) as ajuste,
  (l.marcado - coalesce(e.extrato, 0) - coalesce(aj.ajuste, 0))::numeric(14, 2) as diferenca,
  case
    when abs(l.marcado - coalesce(e.extrato, 0) - coalesce(aj.ajuste, 0)) <= cfg.tolerancia
      then 'conferido'
    when coalesce(e.extrato, 0) = 0 then 'sem_extrato'
    when l.marcado - coalesce(e.extrato, 0) - coalesce(aj.ajuste, 0) > 0
      then 'falta_no_banco'
    else 'sobra_no_banco'
  end as status
from lotes l
cross join cfg
left join extrato e on e.lote = l.lote
left join ajustes aj on aj.data = l.data_lote
where public.usuario_pode_acessar_alguma_pagina(array['venda_especie.html'])

union all

select o.data, null::timestamptz, null::text, 0, 0::numeric(14, 2),
       o.extrato, o.qtd_lancamentos, 0::numeric(14, 2),
       (0 - o.extrato)::numeric(14, 2), 'sem_lote'
from orfaos o
where public.usuario_pode_acessar_alguma_pagina(array['venda_especie.html']);

create or replace view public.app_conferencia_deposito_especie_resumo
with (security_barrier = true, security_invoker = false) as
with cfg as (
  select c.conferencia_deposito_desde as inicio,
         c.conta_deposito_id, c.deposito_descricao_padrao, c.fuso_horario,
         public.unidade_principal_nome() as unidade
  from public.configuracao_operacional c where c.singleton
), marcado as (
  select coalesce(sum(v.valor), 0)::numeric(14, 2) as total
  from public.venda_especie v cross join cfg
  where v.unidade = cfg.unidade and v.depositada_em is not null
    and (v.depositada_em at time zone cfg.fuso_horario)::date >= cfg.inicio
), banco as (
  select coalesce(sum(e.valor), 0)::numeric(14, 2) as total,
         max(e.data) as ultimo_deposito
  from private.extrato_bancario_configuravel e cross join cfg
  where e.descricao ilike cfg.deposito_descricao_padrao
    and e.data >= cfg.inicio - greatest(
      0, public.parametro_valor('deposito_janela_anterior_dias', 1)::integer
    )
    and (cfg.conta_deposito_id is null or e.conta_id = cfg.conta_deposito_id)
), extrato_ate as (
  select max(e.data) as ate
  from private.extrato_bancario_configuravel e cross join cfg
  where cfg.conta_deposito_id is null or e.conta_id = cfg.conta_deposito_id
), ajuste as (
  select coalesce(sum(a.valor), 0)::numeric(14, 2) as total
  from public.conferencia_deposito_ajuste a cross join cfg
  where a.desfeito_em is null and a.data >= cfg.inicio
), pendente as (
  select coalesce(sum(v.valor), 0)::numeric(14, 2) as total
  from public.venda_especie v cross join cfg
  where v.unidade = cfg.unidade and v.depositada_em is null
)
select cfg.inicio as desde, m.total as marcado_depositado,
       b.total as recebido_banco, aj.total as ajustes_justificados,
       (m.total - b.total - aj.total)::numeric(14, 2) as diferenca,
       b.ultimo_deposito, ea.ate as extrato_ate, p.total as pendente_deposito
from cfg cross join marcado m cross join banco b cross join extrato_ate ea
cross join ajuste aj cross join pendente p
where public.usuario_pode_acessar_alguma_pagina(array['venda_especie.html']);

comment on view public.app_conferencia_deposito_especie is
  'Lotes de deposito confrontados com a conta, descricao e janelas configuradas.';
comment on view public.app_conferencia_deposito_especie_resumo is
  'Saldo acumulado da conferencia de deposito conforme configuracao operacional.';

revoke all privileges on public.app_conferencia_deposito_especie from public, anon;
revoke all privileges on public.app_conferencia_deposito_especie_resumo from public, anon;
grant select on public.app_conferencia_deposito_especie to authenticated;
grant select on public.app_conferencia_deposito_especie_resumo to authenticated;

commit;
