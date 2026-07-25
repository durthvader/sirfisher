-- =====================================================================
-- Conta Inter (encerrada) e fechamento do buraco do extrato BB 2025
-- =====================================================================
--
-- PROBLEMA
--   1. A conta Inter (titular pessoa fisica, usada pela PRAIA de mai/2025 a
--      jun/2026 para receber vendas Fundopay e pagar despesas) so existe no
--      sistema como historico ate 17/07/2025. O restante (18/07/2025 a
--      20/06/2026, R$ 155 mil de receitas e despesas) nunca foi lancado.
--   2. O extrato BB tem um buraco: o historico BB termina em 16/07/2025 e o
--      raw_bb comecava em 05/01/2026. Os extratos de jul-dez/2025 serao
--      importados no raw_bb, o que exige um corte para a quinzena
--      01-16/07/2025 ja coberta (e classificada) pelo historico.
--   3. Transferencias entre contas do grupo (Inter -> Praia/Pub e
--      BB -> Praia/Pub) estao classificadas no historico como PIX/RECEITAS,
--      inflando a receita da DRE em R$ 44.000 (12 lancamentos confirmados
--      par a par contra o extrato Inter e os extratos BB de 2025).
--
-- SOLUCAO
--   + tabela raw_inter + conta "Inter" (unidade PRAIA, inativa);
--   ~ fato_financeiro: novo braco 'inter' (corte: so apos o fim do
--     historico Inter, preservando a classificacao manual de mai-jul/2025)
--     e corte do braco 'bb' contra o fim do historico BB (mesma logica ja
--     usada para PRAIA/stone). Vendas Fundopay ("Vendas Crédito"/"Vendas
--     Débito") classificam como Recebivel de Cartao; "Transferencia Entre
--     contas" como Transferencia entre Contas; debitos seguem o de_para.
--   + de_para por nome para as contas do proprio grupo (Sir Fisher,
--     Sirfisher, Sir Fisher Pub, Sir Fisher Imprensa, BS, Hemile/Inter),
--     todos -> Transferencia entre Contas.
--   ~ raw_historico: 12 creditos confirmados como transferencia interna
--     (R$ 44.000, set-nov/2025) reclassificados de PIX/RECEITAS para
--     Transferencia entre Contas/CONTABIL. Aprovado pelo usuario.
--   ~ mv_saldo_caixa_diario_detalhado: nova coluna saldo_inter somada ao
--     saldo_total (recriada; as 4 views dependentes sao recriadas iguais).
--   ~ detalhar_saldo_caixa_dia: passa a devolver saldo_inter.
--
-- OBJETOS
--   + public.raw_inter (+ indices, RLS, grants service_role)
--   + conta "Inter" / linhas de_para do grupo (dados, idempotente)
--   ~ public.raw_historico (12 linhas de dados, idempotente)
--   ~ public.fato_financeiro (create or replace)
--   ~ public.mv_saldo_caixa_diario_detalhado (drop cascade + recreate)
--   ~ public.app_gerente_saldo_variacao, public.app_painel_saldo_atual,
--     public.app_painel_saldo_fim_mes, public.painel_fluxo_caixa
--     (recriadas identicas apos o cascade)
--   ~ public.detalhar_saldo_caixa_dia(date) (drop + recreate, nova coluna)
--
-- RISCO: medio. Receita reportada de set-nov/2025 cai R$ 44.000 (corrige
--   dupla contagem). Saldos historicos passam a incluir a Inter. O buraco
--   restante (R$ 28.000 da Inter para conta "Sir Fisher C A" fora do
--   sistema, provavel BNB) fica registrado como pendencia.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. raw_inter
-- ---------------------------------------------------------------------
create table if not exists public.raw_inter (
  id bigserial primary key,
  conta_id bigint references public.conta (id),
  data date not null,
  data_raw text,
  historico text,
  descricao text,
  valor numeric not null,
  saldo numeric,
  dedup_hash text not null,
  importado_em timestamptz not null default now()
);

create unique index if not exists uq_raw_inter_dedup
  on public.raw_inter (dedup_hash);

create index if not exists raw_inter_data_idx
  on public.raw_inter (data);

alter table public.raw_inter enable row level security;

revoke all privileges on table public.raw_inter from public, anon, authenticated;
grant select, insert, update, delete, references, trigger, truncate
  on table public.raw_inter to service_role;
grant usage, select on sequence public.raw_inter_id_seq to service_role;

comment on table public.raw_inter is
  'Extrato da conta Inter (encerrada em jun/2026); carga via 06_importar_inter.py.';

insert into public.conta (nome, banco, unidade_id, ativa)
values ('Inter', 'Inter', (select id from public.unidade where nome = 'PRAIA'), false)
on conflict (nome) do nothing;

-- ---------------------------------------------------------------------
-- 2. de_para: contas do proprio grupo => Transferencia entre Contas
-- ---------------------------------------------------------------------
insert into public.de_para (chave_tipo, chave_valor, categoria, ativo)
select 'nome', t.v, 'Transferencia entre Contas', true
from (values
  ('SIRFISHER'),
  ('SIRFISHERPRAIA'),
  ('SIRFISHERPUB'),
  ('SIRFISHERIMPRENSA'),
  ('SIRFISHERCOMERCIODEALIMENTOSLTDA'),
  ('SIRFISHERPUBCOMERCIODEALIMENTOSLTDA'),
  ('BSINSTITUICAODEPAGAMENTOSA'),
  ('HEMILEALEXANDRESILVA'),
  ('35220527HEMILEALEXANDRESILVA')
) t(v)
where not exists (
  select 1 from public.de_para d
  where d.chave_tipo = 'nome' and d.chave_valor = t.v
);

-- ---------------------------------------------------------------------
-- 3. Reclassificacao dos 12 creditos confirmados como transferencia
--    interna (par a par com o extrato Inter e os extratos BB 2025)
-- ---------------------------------------------------------------------
update public.raw_historico
set categoria = 'Transferencia entre Contas',
    dre_grupo = 'CONTABIL'
where id in (
  42375, -- PRAIA 05/09/2025 5000,00 <- BB (Pix "Sir.fisher")
  42575, -- PRAIA 11/09/2025 5000,00 <- BB (Pix "Sir.fisher")
  43124, -- PRAIA 29/09/2025 2000,00 <- Inter (Hemile)
  43127, -- PUB   29/09/2025 2000,00 <- Inter (Hemile)
  43338, -- PUB   07/10/2025 5000,00 <- Inter (Hemile)
  43377, -- PUB   08/10/2025 2000,00 <- Inter (Hemile)
  43427, -- PRAIA 10/10/2025 5000,00 <- Inter (Hemile)
  43872, -- PUB   23/10/2025 5000,00 <- Inter (Hemile)
  44311, -- PUB   07/11/2025 3000,00 <- BB (Pix "SIR FISHER PUB")
  44312, -- PRAIA 07/11/2025 3000,00 <- BB (Pix "Sir.fisher")
  44552, -- PUB   14/11/2025 5000,00 <- Inter (Hemile)
  44759  -- PRAIA 19/11/2025 2000,00 <- Inter (Hemile)
)
  and movimentacao = 'Crédito'
  and categoria = 'PIX';

-- ---------------------------------------------------------------------
-- 4. fato_financeiro: braco inter + cortes historico Inter/BB
-- ---------------------------------------------------------------------
create or replace view public.fato_financeiro as
with de_para_u as (
  select distinct on (chave_tipo, chave_valor)
    chave_tipo, chave_valor, categoria, fornecedor
  from de_para
  where ativo
  order by chave_tipo, chave_valor, id desc
),
historico as (
  select
    'historico'::text as origem,
    h.id as raw_id,
    h.empresa,
    h.data_hora::date as data_caixa,
    h.data_hora::date as data_competencia,
    h.movimentacao,
    h.tipo,
    h.valor,
    case when h.movimentacao = 'Débito' then h.destino else h.origem end as contraparte_nome,
    case when h.movimentacao = 'Débito' then h.destino_documento else h.origem_documento end as contraparte_doc,
    h.fornecedor,
    h.categoria,
    h.dre_grupo,
    case when coalesce(h.categoria, '') <> '' then 'classificado' else 'excecao' end as status
  from raw_historico h
  where not (h.empresa = 'PRAIA' and h.data_hora::date >= (select min(data_hora)::date from raw_stone_extrato))
     or (h.empresa = 'BB' and h.data_hora::date >= (select min(data) from raw_bb))
),
live_base as (
  select
    'stone_extrato'::text as origem,
    e.id as raw_id,
    'PRAIA'::text as empresa,
    e.data_hora::date as data_caixa,
    e.movimentacao,
    e.tipo,
    e.valor,
    case when e.movimentacao = 'Débito' then e.destino else e.origem end as contraparte_nome,
    case when e.movimentacao = 'Débito' then e.destino_documento else e.origem_documento end as contraparte_doc,
    (e.origem_documento is not null and e.origem_documento = e.destino_documento) as transf_propria
  from raw_stone_extrato e

  union all

  -- BB: so depois do fim do historico BB, para nao duplicar a quinzena
  -- 01-16/07/2025 ja classificada na carga historica.
  select
    'bb'::text as origem,
    b.id as raw_id,
    'BB'::text as empresa,
    b.data as data_caixa,
    case when b.valor < 0 then 'Débito' else 'Crédito' end as movimentacao,
    b.lancamento as tipo,
    b.valor,
    trim(regexp_replace(coalesce(b.detalhes, b.lancamento), '^[0-9/ :.-]+', '')) as contraparte_nome,
    null::text as contraparte_doc,
    false as transf_propria
  from raw_bb b
  where b.data > coalesce(
    (select max(h.data_hora)::date from raw_historico h where h.empresa = 'BB'),
    date '0001-01-01'
  )

  union all

  -- BS Cash: so a partir do corte ja usado para stone_extrato/bb, para nao
  -- duplicar o que o historico ja conta entre 2023 e 2025.
  select
    'bs_cash'::text as origem,
    c.id as raw_id,
    'PRAIA'::text as empresa,
    c.data_hora::date as data_caixa,
    case when c.valor < 0 then 'Débito' else 'Crédito' end as movimentacao,
    c.operacao as tipo,
    c.valor,
    coalesce(nullif(c.favorecido, ''), c.operacao) as contraparte_nome,
    null::text as contraparte_doc,
    false as transf_propria
  from raw_bs_cash c
  where c.data_hora::date >= date '2026-01-01'

  union all

  -- Inter: conta encerrada, carga unica. So depois do fim do historico
  -- Inter (mai-jul/2025), que ja esta classificado manualmente.
  select
    'inter'::text as origem,
    i.id as raw_id,
    'PRAIA'::text as empresa,
    i.data as data_caixa,
    case when i.valor < 0 then 'Débito' else 'Crédito' end as movimentacao,
    i.historico as tipo,
    i.valor,
    coalesce(nullif(trim(i.descricao), ''), i.historico) as contraparte_nome,
    null::text as contraparte_doc,
    false as transf_propria
  from raw_inter i
  where i.data > coalesce(
    (select max(h.data_hora)::date from raw_historico h where h.empresa = 'Inter'),
    date '0001-01-01'
  )
),
live_match as (
  select
    lb.origem, lb.raw_id, lb.empresa, lb.data_caixa, lb.movimentacao, lb.tipo, lb.valor,
    lb.contraparte_nome, lb.contraparte_doc, lb.transf_propria,
    coalesce(dpc.categoria, dpn.categoria) as dp_cat,
    coalesce(dpc.fornecedor, dpn.fornecedor) as dp_forn
  from live_base lb
  left join de_para_u dpc
    on dpc.chave_tipo = 'cnpj'
   and dpc.chave_valor = case
     when lb.contraparte_doc like '%/%' and lb.contraparte_doc not like '%*%' then so_digitos(lb.contraparte_doc)
     else null
   end
  left join de_para_u dpn
    on dpn.chave_tipo = 'nome'
   and dpn.chave_valor = case
     when lb.contraparte_nome ilike 'desconhecido' then null
     else normaliza_nome(lb.contraparte_nome)
   end
),
live_cat as (
  select
    lm.origem, lm.raw_id, lm.empresa, lm.data_caixa, lm.movimentacao, lm.tipo, lm.valor,
    lm.contraparte_nome, lm.contraparte_doc, lm.dp_cat, lm.dp_forn,
    case
      when lm.transf_propria then 'Transferencia entre Contas'
      when lm.dp_cat = 'ANALISAR INDIVIDUAL' then null
      when lm.dp_cat is not null then lm.dp_cat
      when lm.origem = 'stone_extrato' and lm.movimentacao = 'Crédito' then
        case lm.tipo
          when 'Recebível de Cartão' then 'Recebível de Cartão'
          when 'Pix' then 'PIX'
          when 'TED' then 'TED'
          else 'Transação'
        end
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Crédito' then 'Transferencia entre Contas'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Débito' and lm.tipo = 'PAGAMENTO DE REMUNERACAO' then 'Folha Salarial'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Débito' and lm.tipo = 'DEBITO SERVICO REMUNERACAO' then 'Tarifas Bancárias'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Débito' and lm.tipo = 'ESTORNO DE DEPOSITO' then 'Transferencia entre Contas'
      when lm.origem = 'inter' and lm.movimentacao = 'Crédito' and lm.tipo ilike 'vendas%' then 'Recebível de Cartão'
      when lm.origem = 'inter' and lm.tipo ilike 'transferencia%' then 'Transferencia entre Contas'
      else null
    end as cat_final,
    case
      when lm.transf_propria then 'classificado'
      when lm.dp_cat = 'ANALISAR INDIVIDUAL' then 'analise'
      when lm.dp_cat is not null then 'classificado'
      when lm.origem = 'stone_extrato' and lm.movimentacao = 'Crédito' then 'classificado'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Crédito' then 'classificado'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Débito'
       and lm.tipo in ('PAGAMENTO DE REMUNERACAO', 'DEBITO SERVICO REMUNERACAO', 'ESTORNO DE DEPOSITO') then 'classificado'
      when lm.origem = 'inter' and lm.movimentacao = 'Crédito' and lm.tipo ilike 'vendas%' then 'classificado'
      when lm.origem = 'inter' and lm.tipo ilike 'transferencia%' then 'classificado'
      else 'excecao'
    end as status_final
  from live_match lm
),
live as (
  select
    lc.origem, lc.raw_id, lc.empresa, lc.data_caixa, lc.data_caixa as data_competencia,
    lc.movimentacao, lc.tipo, lc.valor, lc.contraparte_nome, lc.contraparte_doc,
    lc.dp_forn as fornecedor, lc.cat_final as categoria, cdf.dre_grupo, lc.status_final as status
  from live_cat lc
  left join categoria_dre cdf on cdf.categoria = lc.cat_final
),
tudo as (
  select origem, raw_id, empresa, data_caixa, data_competencia, movimentacao, tipo, valor,
         contraparte_nome, contraparte_doc, fornecedor, categoria, dre_grupo, status
  from historico
  union all
  select origem, raw_id, empresa, data_caixa, data_competencia, movimentacao, tipo, valor,
         contraparte_nome, contraparte_doc, fornecedor, categoria, dre_grupo, status
  from live
)
select
  t.origem,
  t.raw_id,
  t.empresa,
  t.data_caixa,
  t.data_competencia,
  t.movimentacao,
  t.tipo,
  t.valor,
  t.contraparte_nome,
  t.contraparte_doc,
  t.fornecedor,
  coalesce(am.categoria, t.categoria) as categoria,
  case when am.categoria is not null then cdo.dre_grupo else t.dre_grupo end as dre_grupo,
  case when am.categoria is not null then 'classificado' else t.status end as status,
  case
    when t.empresa = 'PUB' then 'PUB'
    when t.empresa = 'IMPRENSA' then 'IMPRENSA'
    else 'PRAIA'
  end as unidade,
  case when t.movimentacao = 'Crédito' then 'Receita' else 'Despesa' end as natureza,
  (
    (case when am.categoria is not null then cdo.dre_grupo else t.dre_grupo end)
      is distinct from 'TRANSFERENCIA'
    and (
      -- ANALISAR INDIVIDUAL fica de fora da exclusao de CONTABIL: nao ha
      -- confirmacao de que sejam movimentos nao-operacionais (R$ 462 mil
      -- em 2022-2025, pendente de classificacao manual). Continua
      -- entrando na DRE exatamente como antes.
      (case when am.categoria is not null then cdo.dre_grupo else t.dre_grupo end)
        is distinct from 'CONTABIL'
      or coalesce(am.categoria, t.categoria) = 'ANALISAR INDIVIDUAL'
    )
    and (
      -- TEMPORARIO: fatura de cartao entra na DRE nas fontes vivas ate a
      -- importacao itemizada do BTG; historico segue excluido (rollback:
      -- voltar a expressao de 20260735000000).
      (case when am.categoria is not null then cdo.dre_grupo else t.dre_grupo end)
        is distinct from 'CARTÃO DE CRÉDITO'
      or t.origem <> 'historico'
    )
  ) as entra_dre
from tudo t
left join ajuste_manual am on am.origem = t.origem and am.raw_id = t.raw_id
left join categoria_dre cdo on cdo.categoria = am.categoria;

-- ---------------------------------------------------------------------
-- 5. Snapshot diario: nova coluna saldo_inter
--    (drop cascade derruba as 4 views dependentes; recriadas abaixo
--    identicas as definicoes vigentes)
-- ---------------------------------------------------------------------
drop function if exists public.detalhar_saldo_caixa_dia(date);
drop materialized view if exists public.mv_saldo_caixa_diario_detalhado cascade;

create materialized view public.mv_saldo_caixa_diario_detalhado
as
with limites as (
  select
    min(e.data_hora::date) as inicio,
    (select c.dia from public.corte_caixa c limit 1) as fim
  from public.raw_stone_extrato e
  where e.saldo_depois is not null
), dias as (
  select gs::date as dia
  from limites l
  cross join lateral generate_series(
    l.inicio::timestamp,
    l.fim::timestamp,
    interval '1 day'
  ) gs
  where l.inicio is not null
    and l.fim is not null
    and l.fim >= l.inicio
), stone_fechamento as (
  select distinct on (e.data_hora::date)
    e.data_hora::date as dia,
    e.saldo_depois as saldo
  from public.raw_stone_extrato e
  cross join limites l
  where e.saldo_depois is not null
    and e.data_hora::date >= l.inicio
    and e.data_hora::date <= l.fim
  order by e.data_hora::date, e.data_hora desc, e.id desc
), bb_base as (
  select coalesce((
    select si.saldo
    from public.saldo_inicial si
    where lower(si.conta) = 'bb'
    limit 1
  ), 0::numeric) as saldo
), bb_antes as (
  select coalesce(sum(b.valor), 0::numeric) as total
  from public.raw_bb b
  cross join limites l
  where b.data < l.inicio
), bb_movimentos as (
  select b.data as dia, sum(b.valor) as total
  from public.raw_bb b
  cross join limites l
  where b.data >= l.inicio
    and b.data <= l.fim
  group by b.data
), bb_diario as (
  select
    d.dia,
    bb.saldo + ant.total
      + sum(coalesce(m.total, 0::numeric)) over (
          order by d.dia rows between unbounded preceding and current row
        ) as saldo
  from dias d
  cross join bb_base bb
  cross join bb_antes ant
  left join bb_movimentos m on m.dia = d.dia
), inter_antes as (
  -- A conta Inter nasceu em mai/2025 com saldo zero; o extrato importado
  -- cobre a vida inteira da conta, entao a soma acumulada e o saldo.
  select coalesce(sum(i.valor), 0::numeric) as total
  from public.raw_inter i
  cross join limites l
  where i.data < l.inicio
), inter_movimentos as (
  select i.data as dia, sum(i.valor) as total
  from public.raw_inter i
  cross join limites l
  where i.data >= l.inicio
    and i.data <= l.fim
  group by i.data
), inter_diario as (
  select
    d.dia,
    ant.total
      + sum(coalesce(m.total, 0::numeric)) over (
          order by d.dia rows between unbounded preceding and current row
        ) as saldo
  from dias d
  cross join inter_antes ant
  left join inter_movimentos m on m.dia = d.dia
), especie_eventos as (
  select v.data as dia, v.valor as valor
  from public.venda_especie v
  where v.unidade = 'PRAIA'

  union all

  select
    (v.depositada_em at time zone 'America/Fortaleza')::date as dia,
    -v.valor as valor
  from public.venda_especie v
  where v.unidade = 'PRAIA'
    and v.depositada_em is not null
), especie_antes as (
  select coalesce(sum(e.valor), 0::numeric) as total
  from especie_eventos e
  cross join limites l
  where e.dia < l.inicio
), especie_movimentos as (
  select e.dia, sum(e.valor) as total
  from especie_eventos e
  cross join limites l
  where e.dia >= l.inicio
    and e.dia <= l.fim
  group by e.dia
), especie_diario as (
  select
    d.dia,
    ant.total as saldo_anterior,
    ant.total
      + sum(coalesce(m.total, 0::numeric)) over (
          order by d.dia rows between unbounded preceding and current row
        ) as saldo
  from dias d
  cross join especie_antes ant
  left join especie_movimentos m on m.dia = d.dia
), componentes as (
  select
    d.dia,
    coalesce(sf.saldo, 0::numeric) as saldo_stone,
    coalesce(bb.saldo, 0::numeric) as saldo_bb,
    coalesce(it.saldo, 0::numeric) as saldo_inter,
    coalesce(ep.saldo, 0::numeric) as dinheiro_pendente,
    coalesce(ep.saldo_anterior, 0::numeric) as dinheiro_pendente_anterior
  from dias d
  left join lateral (
    select s.saldo
    from stone_fechamento s
    where s.dia <= d.dia
    order by s.dia desc
    limit 1
  ) sf on true
  left join bb_diario bb on bb.dia = d.dia
  left join inter_diario it on it.dia = d.dia
  left join especie_diario ep on ep.dia = d.dia
), normalizados as (
  select
    c.dia,
    round(c.saldo_stone, 2) as saldo_stone,
    round(c.saldo_bb, 2) as saldo_bb,
    round(c.saldo_inter, 2) as saldo_inter,
    round(c.dinheiro_pendente, 2) as dinheiro_pendente,
    round(c.dinheiro_pendente_anterior, 2) as dinheiro_pendente_anterior
  from componentes c
)
select
  n.dia,
  n.saldo_stone,
  n.saldo_bb,
  n.saldo_inter,
  n.dinheiro_pendente,
  round(
    n.dinheiro_pendente
      - lag(
          n.dinheiro_pendente,
          1,
          n.dinheiro_pendente_anterior
        ) over (order by n.dia),
    2
  ) as variacao_dinheiro_pendente,
  round(n.saldo_stone + n.saldo_bb + n.saldo_inter + n.dinheiro_pendente, 2) as saldo_total
from normalizados n
order by n.dia
with data;

create unique index if not exists mv_saldo_caixa_diario_detalhado_dia_idx
  on public.mv_saldo_caixa_diario_detalhado (dia);

revoke all privileges on table public.mv_saldo_caixa_diario_detalhado
  from public, anon, authenticated;

comment on materialized view public.mv_saldo_caixa_diario_detalhado is
  'Snapshot diario do caixa realizado: Stone, BB, Inter, dinheiro pendente na data, variacao do dinheiro e total.';

-- ---------------------------------------------------------------------
-- 6. Views dependentes recriadas identicas as definicoes vigentes
-- ---------------------------------------------------------------------
create or replace view public.painel_fluxo_caixa as
select f.dia,
  f.tipo,
  case when f.tipo = 'real' then coalesce(d.saldo_total, f.saldo) else f.saldo end as saldo,
  case when f.tipo = 'real' then coalesce(d.saldo_total, f.saldo) else null::numeric end as saldo_real,
  case when f.tipo = 'projetado' then f.saldo else null::numeric end as saldo_projetado,
  f.entrada_projetada,
  f.saida_projetada,
  case
    when f.tipo = 'real' and d.dia is not null and f.resultado_dia is not null
      then round(f.resultado_dia + coalesce(d.variacao_dinheiro_pendente, 0::numeric), 2)
    else f.resultado_dia
  end as resultado_dia
from mv_fluxo_caixa_diario f
left join mv_saldo_caixa_diario_detalhado d on d.dia = f.dia
order by f.dia;

revoke all privileges on table public.painel_fluxo_caixa
  from public, anon, authenticated;

create or replace view public.app_painel_saldo_atual
with (security_barrier = true, security_invoker = false) as
select s.data_ref,
  s.saldo_atual,
  s.data_comp,
  coalesce(comp.saldo_total, s.saldo_comp) as saldo_comp
from painel_saldo_atual s
left join lateral (
  select d.saldo_total
  from mv_saldo_caixa_diario_detalhado d
  where d.dia <= s.data_comp
  order by d.dia desc
  limit 1
) comp on true
where usuario_tem_papel(array['admin'::text, 'socio'::text]);

revoke all privileges on table public.app_painel_saldo_atual
  from public, anon, authenticated;
grant select on public.app_painel_saldo_atual to authenticated;

create or replace view public.app_painel_saldo_fim_mes
with (security_barrier = true, security_invoker = false) as
with corte as (
  select max(d.dia) as dia
  from mv_saldo_caixa_diario_detalhado d
), ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes,
    d.saldo_total
  from mv_saldo_caixa_diario_detalhado d
  order by date_trunc('month', d.dia)::date, d.dia desc
)
select s.mes,
  s.ano_mes,
  case
    when s.mes < date_trunc('month', c.dia)::date then coalesce(u.saldo_total, s.saldo_fim)
    else s.saldo_fim
  end as saldo_fim,
  s.situacao
from painel_saldo_fim_mes s
cross join corte c
left join ultimo_snapshot_mes u on u.mes = s.mes
where usuario_tem_papel(array['admin'::text, 'socio'::text]);

revoke all privileges on table public.app_painel_saldo_fim_mes
  from public, anon, authenticated;
grant select on public.app_painel_saldo_fim_mes to authenticated;

create or replace view public.app_gerente_saldo_variacao
with (security_barrier = true, security_invoker = false) as
with corte as (
  select max(d.dia) as dia
  from mv_saldo_caixa_diario_detalhado d
), ultimo_snapshot_mes as (
  select distinct on (date_trunc('month', d.dia)::date)
    date_trunc('month', d.dia)::date as mes,
    d.saldo_total
  from mv_saldo_caixa_diario_detalhado d
  order by date_trunc('month', d.dia)::date, d.dia desc
), saldos as (
  select s_1.ano_mes,
    case
      when s_1.mes < date_trunc('month', c.dia)::date then coalesce(u.saldo_total, s_1.saldo_fim)
      else s_1.saldo_fim
    end as saldo_fim
  from painel_saldo_fim_mes s_1
  cross join corte c
  left join ultimo_snapshot_mes u on u.mes = s_1.mes
)
select ano_mes,
  round(100.0 * (saldo_fim - lag(saldo_fim) over (order by ano_mes))
    / nullif(abs(lag(saldo_fim) over (order by ano_mes)), 0::numeric), 1) as variacao_perc
from saldos s
where usuario_tem_papel(array['admin'::text, 'socio'::text, 'gerente'::text]);

revoke all privileges on table public.app_gerente_saldo_variacao
  from public, anon, authenticated;
grant select on public.app_gerente_saldo_variacao to authenticated;

-- ---------------------------------------------------------------------
-- 7. detalhar_saldo_caixa_dia com saldo_inter
-- ---------------------------------------------------------------------
create or replace function public.detalhar_saldo_caixa_dia(p_dia date)
returns table (
  dia date,
  saldo_stone numeric,
  saldo_bb numeric,
  saldo_inter numeric,
  dinheiro_pendente numeric,
  saldo_total numeric
)
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
    s.dia,
    s.saldo_stone,
    s.saldo_bb,
    s.saldo_inter,
    s.dinheiro_pendente,
    s.saldo_total
  from public.mv_saldo_caixa_diario_detalhado s
  where s.dia = p_dia;
end;
$function$;

comment on function public.detalhar_saldo_caixa_dia(date) is
  'Composicao materializada do saldo realizado do Calendario em uma data (Stone, BB, Inter e dinheiro).';

revoke all privileges on function public.detalhar_saldo_caixa_dia(date)
  from public, anon, authenticated;
grant execute on function public.detalhar_saldo_caixa_dia(date)
  to authenticated;

commit;
