-- Faz os consumidores vigentes lerem unidade, fontes e parametros cadastrados.
-- Os defaults reproduzem as regras anteriores.

begin;

-- Guarda o resultado vigente dentro da mesma transacao. Se qualquer view
-- parametrizada mudar uma linha com os defaults migrados, a migration aborta
-- e volta integralmente, em vez de publicar numeros diferentes em silencio.
drop table if exists pg_temp.p1_antes_recebimento_stone_net;
create temporary table p1_antes_recebimento_stone_net on commit drop
as select * from public.recebimento_stone_net;
drop table if exists pg_temp.p1_antes_recebimento_transacao_net;
create temporary table p1_antes_recebimento_transacao_net on commit drop
as select * from public.recebimento_transacao_net;
drop table if exists pg_temp.p1_antes_venda_diaria;
create temporary table p1_antes_venda_diaria on commit drop
as select * from public.venda_diaria;
drop table if exists pg_temp.p1_antes_recebimento_resumo;
create temporary table p1_antes_recebimento_resumo on commit drop
as select * from public.painel_recebimento_resumo;
drop table if exists pg_temp.p1_antes_recebimento_canal;
create temporary table p1_antes_recebimento_canal on commit drop
as select * from public.painel_recebimento_canal;
drop table if exists pg_temp.p1_antes_recebimento_hora;
create temporary table p1_antes_recebimento_hora on commit drop
as select * from public.painel_recebimento_hora;
drop table if exists pg_temp.p1_antes_projecao_venda;
create temporary table p1_antes_projecao_venda on commit drop
as select * from public.projecao_venda_diaria;
drop table if exists pg_temp.p1_antes_projecao_fixa;
create temporary table p1_antes_projecao_fixa on commit drop
as select * from public.projecao_despesa_fixa;
drop table if exists pg_temp.p1_antes_colchao_fixa;
create temporary table p1_antes_colchao_fixa on commit drop
as select * from public.painel_colchao_despesa_fixa;
drop table if exists pg_temp.p1_antes_caixa_real;
create temporary table p1_antes_caixa_real on commit drop
as select * from public.caixa_real_diario;

-- ---------------------------------------------------------------------------
-- Faturamento: contas Stone pertencem a unidade unica, preservando o estado
-- vigente de inclusao de cada codigo.
-- ---------------------------------------------------------------------------

create or replace view public.recebimento_stone_net as
with mapa_terminal as (
  select n_serie, min(stonecode) as stonecode
  from public.raw_stone_vendas
  where stonecode is not null and n_serie is not null
  group by n_serie
), cancelado as (
  select r.stone_id, sum(abs(r.valor_bruto)) as cancelado
  from public.raw_stone_recebiveis r
  where r.categoria ilike '%cancelamento%'
  group by r.stone_id
)
select
  v.id,
  v.data_venda,
  v.produto,
  v.bandeira,
  v.valor_bruto - coalesce(c.cancelado, 0::numeric) as bruto_net
from public.raw_stone_vendas v
left join mapa_terminal m on m.n_serie = v.n_serie
left join public.stone_conta sc
  on sc.stonecode = coalesce(v.stonecode, m.stonecode)
left join cancelado c on c.stone_id = v.stone_id
where v.data_venda is not null
  and exists (
    select 1 from public.fonte_financeira f
    where f.chave = 'stone_vendas' and f.ativa and f.entra_faturamento
  )
  and coalesce(sc.ativa and sc.entra_faturamento, true);

comment on view public.recebimento_stone_net is
  'Vendas das contas Stone habilitadas no faturamento da unidade unica, liquidas de cancelamento. Codigo Stone identifica conta/origem, nao unidade.';

create or replace view public.recebimento_transacao_net as
select
  'stone'::text as fonte,
  s.id,
  s.data_venda,
  s.produto,
  s.bandeira,
  s.bruto_net
from public.recebimento_stone_net s

union all

select
  'fundopay'::text as fonte,
  f.id,
  (f.data_venda at time zone 'UTC') as data_venda,
  f.modalidade as produto,
  f.bandeira,
  f.valor_venda as bruto_net
from public.raw_fundopay_vendas f
where lower(btrim(f.situacao)) = 'aprovada'
  and exists (
    select 1 from public.fonte_financeira x
    where x.chave = 'fundopay' and x.ativa and x.entra_faturamento
  );

create or replace view public.venda_diaria as
select dia, sum(bruto) as bruto, sum(qtd) as qtd_vendas
from (
  select s.data_venda::date as dia, s.bruto_net as bruto, 1 as qtd
  from public.recebimento_stone_net s

  union all

  select e.data, e.valor, 0
  from public.venda_especie e
  where e.unidade = public.unidade_principal_nome()
    and exists (
      select 1 from public.fonte_financeira f
      where f.chave = 'venda_especie' and f.ativa and f.entra_faturamento
    )

  union all

  select f.data_venda::date, f.valor_venda::numeric, 1
  from public.raw_fundopay_vendas f
  where lower(btrim(f.situacao)) = 'aprovada'
    and exists (
      select 1 from public.fonte_financeira x
      where x.chave = 'fundopay' and x.ativa and x.entra_faturamento
    )

  union all

  select (b.data - 1), b.valor::numeric, 1
  from public.raw_bb b
  where b.lancamento = 'Pix-Recebido QR Code'
    and b.valor > 0
    and exists (
      select 1 from public.fonte_financeira f
      where f.chave = 'bb_pix_qr' and f.ativa and f.entra_faturamento
    )
) x
group by dia;

comment on view public.venda_diaria is
  'Faturamento diario da unidade unica, composto pelas fontes ativas marcadas para entrar no faturamento.';

create or replace view public.painel_recebimento_resumo as
with tx as (
  select to_char(t.data_venda, 'YYYY-MM') as ano_mes,
         date_trunc('month', t.data_venda)::date as mes,
         sum(t.bruto_net) as bruto, count(*) as qtd
  from public.recebimento_transacao_net t
  group by 1, 2
), pix_bb as (
  select to_char(b.data - 1, 'YYYY-MM') as ano_mes,
         date_trunc('month', b.data - 1)::date as mes,
         sum(b.valor) as bruto, count(*) as qtd
  from public.raw_bb b
  where b.lancamento = 'Pix-Recebido QR Code' and b.valor > 0
    and exists (
      select 1 from public.fonte_financeira f
      where f.chave = 'bb_pix_qr' and f.ativa and f.entra_faturamento
    )
  group by 1, 2
), esp as (
  select to_char(e.data, 'YYYY-MM') as ano_mes,
         date_trunc('month', e.data)::date as mes,
         sum(e.valor) as valor
  from public.venda_especie e
  where e.unidade = public.unidade_principal_nome()
    and exists (
      select 1 from public.fonte_financeira f
      where f.chave = 'venda_especie' and f.ativa and f.entra_faturamento
    )
  group by 1, 2
), tudo as (
  select ano_mes, mes, bruto, qtd, 0::numeric as especie from tx
  union all select ano_mes, mes, bruto, qtd, 0::numeric from pix_bb
  union all select ano_mes, mes, 0::numeric, 0::bigint, valor from esp
)
select ano_mes, mes,
       round(sum(bruto) + sum(especie), 2) as recebido_total,
       sum(qtd)::bigint as qtd_transacoes,
       round(sum(bruto) / nullif(sum(qtd), 0)::numeric, 2) as ticket_transacao
from tudo
group by ano_mes, mes
order by ano_mes;

create or replace view public.painel_recebimento_canal as
with fonte as (
  select to_char(t.data_venda, 'YYYY-MM') as ano_mes,
         coalesce(nullif(t.produto, ''), 'Cartao') as canal,
         t.bruto_net as valor, 1::bigint as qtd
  from public.recebimento_transacao_net t
  union all
  select to_char(b.data - 1, 'YYYY-MM'), 'Pix QRcode'::text, b.valor, 1::bigint
  from public.raw_bb b
  where b.lancamento = 'Pix-Recebido QR Code' and b.valor > 0
    and exists (
      select 1 from public.fonte_financeira f
      where f.chave = 'bb_pix_qr' and f.ativa and f.entra_faturamento
    )
)
select ano_mes, canal, round(sum(valor), 2) as valor, sum(qtd)::bigint as qtd
from fonte
group by ano_mes, canal
union all
select to_char(e.data, 'YYYY-MM'), 'Especie'::text, round(sum(e.valor), 2), null::bigint
from public.venda_especie e
where e.unidade = public.unidade_principal_nome()
  and exists (
    select 1 from public.fonte_financeira f
    where f.chave = 'venda_especie' and f.ativa and f.entra_faturamento
  )
group by 1
order by 1, 3 desc;

create or replace view public.painel_recebimento_hora as
select to_char(t.data_venda, 'YYYY-MM') as ano_mes,
       extract(hour from t.data_venda)::integer as hora,
       round(sum(t.bruto_net), 2) as valor,
       count(*) as qtd
from public.recebimento_transacao_net t
group by 1, 2
order by 1, 2;

-- ---------------------------------------------------------------------------
-- Meta e despesas fixas usam os parametros editaveis.
-- ---------------------------------------------------------------------------

create or replace view public.projecao_venda_diaria as
with corte as (
  select dia from public.corte_venda
), mes_corte as (
  select date_trunc('month', cv.dia::timestamp with time zone)::date as mes
  from public.corte_venda cv
), venda_por_mes as (
  select date_trunc('month', v.dia::timestamp with time zone)::date as mes,
         sum(v.bruto) as bruto
  from public.venda_diaria v group by 1
), meta_principal as (
  select m.mes, m.meta_bruta
  from public.meta_mensal m
  where m.unidade = public.unidade_principal_nome()
), meses as (
  select distinct c.mes from public.calendario c
), mes_total as (
  select ms.mes,
    case
      when ms.mes < mc.mes then coalesce(vm.bruto, 0::numeric)
      when ms.mes = mc.mes then coalesce(t.tendencia, mp.meta_bruta)
      else mp.meta_bruta
    end as total_esperado,
    pm.peso_total
  from meses ms
  cross join mes_corte mc
  left join venda_por_mes vm on vm.mes = ms.mes
  left join meta_principal mp on mp.mes = ms.mes
  left join public.peso_mensal pm on pm.mes = ms.mes
  left join lateral (select tm.tendencia from public.tendencia_mes tm) t on true
)
select c.dia, c.mes, c.peso_ajustado as peso,
  case
    when c.dia <= (select ct.dia from corte ct) then coalesce(v.bruto, 0::numeric)
    else round(coalesce(mt.total_esperado, 0::numeric) * c.peso_ajustado
               / nullif(mt.peso_total, 0::numeric), 2)
  end as venda,
  case when c.dia <= (select ct.dia from corte ct)
       then 'real'::text else 'projetado'::text end as tipo
from public.calendario c
left join public.venda_diaria v on v.dia = c.dia
left join mes_total mt on mt.mes = c.mes;

create or replace view public.projecao_despesa_fixa as
with cfg as (
  select greatest(1, public.parametro_valor('meses_media_fixa', 3)::integer) as meses
), corte as (
  select dia from public.corte_caixa
), media as (
  select coalesce(avg(m.total), 0::numeric) as media_mensal
  from (
    select date_trunc('month', f.data_competencia) as mes, sum(abs(f.valor)) as total
    from public.fato_financeiro f cross join cfg
    where f.movimentacao like 'D%'
      and f.dre_grupo = any (array['PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'])
      and f.data_competencia >= date_trunc('month', current_date) - make_interval(months => cfg.meses)
      and f.data_competencia < date_trunc('month', current_date)
    group by 1
  ) m
), realizado_mes as (
  select date_trunc('month', f.data_competencia) as mes, sum(abs(f.valor)) as realizado
  from public.fato_financeiro f
  where f.movimentacao like 'D%'
    and f.dre_grupo = any (array['PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'])
  group by 1
), dias_restantes as (
  select c.mes, count(*) as n
  from public.calendario c cross join corte ct
  where c.dia > ct.dia group by c.mes
), contas_abertas as (
  select dr.mes,
    case when v.vencimento > ct.dia then v.vencimento
         else (select min(c.dia) from public.calendario c where c.mes = dr.mes and c.dia > ct.dia)
    end as dia,
    m.media_periodo as valor
  from dias_restantes dr
  cross join corte ct
  cross join cfg
  join public.conta_recorrente cr on cr.ativa and cr.tipo = 'despesa' and cr.incluir_totais
  cross join lateral (
    select least((dr.mes + (cr.dia_vencimento - 1) * interval '1 day')::date,
                 (dr.mes + interval '1 month - 1 day')::date) as vencimento
  ) v
  left join public.conta_recorrente_pagamento cp
    on cp.conta_id = cr.id and cp.competencia = dr.mes
  cross join lateral (
    select round(avg(h.valor), 2) as media_periodo
    from (
      select p.valor from public.conta_recorrente_pagamento p
      where p.conta_id = cr.id and p.competencia < dr.mes
        and p.situacao = 'pago' and p.valor > 0
      order by p.competencia desc limit (select meses from cfg)
    ) h
  ) m
  where cp.id is null and m.media_periodo > 0
), contas_abertas_mes as (
  select mes, sum(valor) as total from contas_abertas group by mes
), contas_abertas_dia as (
  select dia, sum(valor) as total from contas_abertas where dia is not null group by dia
)
select c.dia,
  round(greatest((select media_mensal from media) - coalesce(rm.realizado, 0)
                 - coalesce(cam.total, 0), 0) / dr.n::numeric
        + coalesce(cad.total, 0), 2) as valor
from public.calendario c
join dias_restantes dr on dr.mes = c.mes
left join realizado_mes rm on rm.mes = c.mes
left join contas_abertas_mes cam on cam.mes = c.mes
left join contas_abertas_dia cad on cad.dia = c.dia
cross join corte ct
where c.dia > ct.dia;

create or replace view public.painel_colchao_despesa_fixa as
with cfg as (
  select greatest(1, public.parametro_valor('meses_media_fixa', 3)::integer) as meses
), corte as (
  select dia from public.corte_caixa
), media as (
  select coalesce(avg(m.total), 0::numeric) as media_mensal
  from (
    select date_trunc('month', f.data_competencia) as mes, sum(abs(f.valor)) as total
    from public.fato_financeiro f cross join cfg
    where f.movimentacao like 'D%'
      and f.dre_grupo = any (array['PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'])
      and f.data_competencia >= date_trunc('month', current_date) - make_interval(months => cfg.meses)
      and f.data_competencia < date_trunc('month', current_date)
    group by 1
  ) m
), realizado_mes as (
  select date_trunc('month', f.data_competencia) as mes, sum(abs(f.valor)) as realizado
  from public.fato_financeiro f
  where f.movimentacao like 'D%'
    and f.dre_grupo = any (array['PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'])
  group by 1
), dias_restantes as (
  select c.mes, count(*) as n from public.calendario c cross join corte ct
  where c.dia > ct.dia group by c.mes
), contas_abertas as (
  select dr.mes, m.media_periodo as valor
  from dias_restantes dr cross join cfg
  join public.conta_recorrente cr on cr.ativa and cr.tipo = 'despesa' and cr.incluir_totais
  left join public.conta_recorrente_pagamento cp
    on cp.conta_id = cr.id and cp.competencia = dr.mes
  cross join lateral (
    select round(avg(h.valor), 2) as media_periodo
    from (
      select p.valor from public.conta_recorrente_pagamento p
      where p.conta_id = cr.id and p.competencia < dr.mes
        and p.situacao = 'pago' and p.valor > 0
      order by p.competencia desc limit (select meses from cfg)
    ) h
  ) m
  where cp.id is null and m.media_periodo > 0
), contas_abertas_mes as (
  select mes, sum(valor) as total from contas_abertas group by mes
)
select dr.mes,
  round((select media_mensal from media), 2) as media_tipica,
  round(coalesce(rm.realizado, 0), 2) as ja_realizado,
  round(greatest((select media_mensal from media) - coalesce(rm.realizado, 0)
                 - coalesce(cam.total, 0), 0), 2) as colchao,
  dr.n as dias_restantes,
  round(greatest((select media_mensal from media) - coalesce(rm.realizado, 0)
                 - coalesce(cam.total, 0), 0) / dr.n::numeric, 2) as valor_dia,
  round(coalesce(cam.total, 0), 2) as contas_abertas
from dias_restantes dr
left join realizado_mes rm on rm.mes = dr.mes
left join contas_abertas_mes cam on cam.mes = dr.mes
order by dr.mes;

-- Caixa respeita o cadastro de fontes. Para o historico consolidado, nomes
-- antigos de empresa/conta sao resolvidos contra chaves e nomes configurados.
create or replace view public.caixa_real_diario as
select f.data_caixa as dia, sum(f.valor) as resultado_real
from public.fato_financeiro f
left join public.fonte_financeira cfg on cfg.chave = f.origem
where (
    (cfg.chave is not null and cfg.ativa and cfg.entra_caixa)
    or (cfg.chave is null and (
      upper(coalesce(f.empresa, '')) = upper(public.unidade_principal_nome())
      or exists (
        select 1
        from public.fonte_financeira lf
        left join public.conta c on c.id = lf.conta_id
        where lf.ativa and lf.entra_caixa and lf.entra_caixa_historico
          and regexp_replace(lower(coalesce(f.empresa, '')), '[^a-z0-9]+', '', 'g')
              = any (array[
                  regexp_replace(lower(lf.chave), '[^a-z0-9]+', '', 'g'),
                  regexp_replace(lower(lf.nome), '[^a-z0-9]+', '', 'g'),
                  regexp_replace(lower(coalesce(c.nome, '')), '[^a-z0-9]+', '', 'g'),
                  regexp_replace(lower(coalesce(c.banco, '')), '[^a-z0-9]+', '', 'g')
                ])
      )
    ))
  )
group by f.data_caixa;

-- Bonificacao conserva percentual e teto anteriores como defaults.
create or replace view public.app_gerente_saldo_variacao
with (security_barrier = true, security_invoker = false) as
with corte as (
  select max(d.dia) as dia from public.mv_saldo_caixa_diario_detalhado d
), ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes, d.saldo_total
  from public.mv_saldo_caixa_diario_detalhado d
  order by date_trunc('month', d.dia)::date, d.dia desc
), saldos as (
  select s.ano_mes,
    case when s.mes < date_trunc('month', c.dia)::date
         then coalesce(u.saldo_total, s.saldo_fim) else s.saldo_fim end as saldo_fim
  from public.painel_saldo_fim_mes s
  cross join corte c left join ultimo_snapshot_mes u on u.mes = s.mes
), comparacao as (
  select s.ano_mes, s.saldo_fim,
         lag(s.saldo_fim) over (order by s.ano_mes) as saldo_anterior
  from saldos s
)
select c.ano_mes,
  round(100.0 * (c.saldo_fim - c.saldo_anterior)
        / nullif(abs(c.saldo_anterior), 0::numeric), 1) as variacao_perc,
  case when c.saldo_anterior is null then null::numeric
       else least(
         round(greatest(c.saldo_fim - c.saldo_anterior, 0::numeric)
               * public.parametro_valor('bonus_gerente_percentual', 2) / 100, 2),
         public.parametro_valor('bonus_gerente_teto', 600)
       ) end as previsao_bonificacao
from comparacao c
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

revoke all privileges on table public.app_gerente_saldo_variacao from public, anon, authenticated;
grant select on table public.app_gerente_saldo_variacao to authenticated;

do $validacao$
begin
  if exists (
    (select * from pg_temp.p1_antes_recebimento_stone_net
     except all select * from public.recebimento_stone_net)
    union all
    (select * from public.recebimento_stone_net
     except all select * from pg_temp.p1_antes_recebimento_stone_net)
  ) then raise exception 'Regressao numerica em recebimento_stone_net.'; end if;

  if exists (
    (select * from pg_temp.p1_antes_recebimento_transacao_net
     except all select * from public.recebimento_transacao_net)
    union all
    (select * from public.recebimento_transacao_net
     except all select * from pg_temp.p1_antes_recebimento_transacao_net)
  ) then raise exception 'Regressao numerica em recebimento_transacao_net.'; end if;

  if exists (
    (select * from pg_temp.p1_antes_venda_diaria
     except all select * from public.venda_diaria)
    union all
    (select * from public.venda_diaria
     except all select * from pg_temp.p1_antes_venda_diaria)
  ) then raise exception 'Regressao numerica em venda_diaria.'; end if;

  if exists (
    (select * from pg_temp.p1_antes_recebimento_resumo
     except all select * from public.painel_recebimento_resumo)
    union all
    (select * from public.painel_recebimento_resumo
     except all select * from pg_temp.p1_antes_recebimento_resumo)
  ) then raise exception 'Regressao numerica em painel_recebimento_resumo.'; end if;

  if exists (
    (select * from pg_temp.p1_antes_recebimento_canal
     except all select * from public.painel_recebimento_canal)
    union all
    (select * from public.painel_recebimento_canal
     except all select * from pg_temp.p1_antes_recebimento_canal)
  ) then raise exception 'Regressao numerica em painel_recebimento_canal.'; end if;

  if exists (
    (select * from pg_temp.p1_antes_recebimento_hora
     except all select * from public.painel_recebimento_hora)
    union all
    (select * from public.painel_recebimento_hora
     except all select * from pg_temp.p1_antes_recebimento_hora)
  ) then raise exception 'Regressao numerica em painel_recebimento_hora.'; end if;

  if exists (
    (select * from pg_temp.p1_antes_projecao_venda
     except all select * from public.projecao_venda_diaria)
    union all
    (select * from public.projecao_venda_diaria
     except all select * from pg_temp.p1_antes_projecao_venda)
  ) then raise exception 'Regressao numerica em projecao_venda_diaria.'; end if;

  if exists (
    (select * from pg_temp.p1_antes_projecao_fixa
     except all select * from public.projecao_despesa_fixa)
    union all
    (select * from public.projecao_despesa_fixa
     except all select * from pg_temp.p1_antes_projecao_fixa)
  ) then raise exception 'Regressao numerica em projecao_despesa_fixa.'; end if;

  if exists (
    (select * from pg_temp.p1_antes_colchao_fixa
     except all select * from public.painel_colchao_despesa_fixa)
    union all
    (select * from public.painel_colchao_despesa_fixa
     except all select * from pg_temp.p1_antes_colchao_fixa)
  ) then raise exception 'Regressao numerica em painel_colchao_despesa_fixa.'; end if;

  if exists (
    (select * from pg_temp.p1_antes_caixa_real
     except all select * from public.caixa_real_diario)
    union all
    (select * from public.caixa_real_diario
     except all select * from pg_temp.p1_antes_caixa_real)
  ) then raise exception 'Regressao numerica em caixa_real_diario.'; end if;
end;
$validacao$;

commit;
