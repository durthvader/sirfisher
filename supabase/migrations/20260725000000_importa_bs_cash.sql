-- =====================================================================
-- Nova fonte de importacao: conta "BS Cash" (usada para folha de pagamento)
-- =====================================================================
--
-- PROBLEMA
--   A folha de pagamento ("Salarios + bonificacao", registrada em
--   conta_recorrente_pagamento) nunca aparece em fato_financeiro no dia do
--   pagamento - o calendario financeiro (calendario.html) mostra o total do
--   dia muito abaixo do real e um aviso de "nao conciliada" (as vezes
--   dezenas de milhares de reais). Causa: a folha e paga pela conta "BS
--   Cash", uma fonte que nunca foi importada (so Stone/BB/historico
--   existiam ate aqui).
--
-- ESCOPO (importante)
--   O extrato fornecido cobre 08/2023 a 06/2026 (960 lancamentos), mas
--   raw_historico ja tem 23.253 linhas empresa='PRAIA' entre 08/2023 e
--   12/2025 contadas em fato_financeiro (o filtro que exclui o historico so
--   vale a partir de 01/01/2026 - mesma data de corte em que
--   stone_extrato/bb assumiram). Incluir o extrato BS Cash inteiro
--   duplicaria anos de despesas/receitas ja contadas pelo historico.
--   Por isso: importamos o CSV inteiro para raw_bs_cash (nada se perde),
--   mas so incluimos no fato_financeiro (calendario/despesas/DRE/caixa)
--   lancamentos >= 01/01/2026 - mesmo corte ja usado para stone_extrato/bb.
--   Fechar 2023-2025 exigiria reconciliar transacao a transacao contra o
--   historico (fora de escopo aqui; os dados brutos ficam preservados para
--   isso no futuro, se desejado).
--
-- OBJETOS
--   + raw_bs_cash            (nova tabela, mesmo padrao de raw_bb)
--   + conta 'BS Cash'         (novo cadastro, exigido pelo importador)
--   ~ fato_financeiro         (create or replace view; novo braco 'bs_cash'
--                              dentro de live_base, com filtro >= 2026-01-01;
--                              nenhuma coluna de saida muda)
--
-- RISCO: baixo.
--   - raw_bs_cash e tabela nova; grants replicam raw_bb (so postgres/
--     service_role - o importador conecta via DATABASE_URL, nao pelo
--     PostgREST).
--   - fato_financeiro mantem exatamente as mesmas colunas de saida; so
--     acrescenta um braco a mais dentro do UNION ALL interno (live_base).
--   - Sem o filtro de data, o risco seria duplicar anos de historico; com
--     o filtro, e estritamente aditivo (preenche um buraco que hoje e
--     zero).
-- =====================================================================

begin;

create table if not exists public.raw_bs_cash (
  id bigint generated always as identity primary key,
  conta_id smallint,
  data_hora timestamp without time zone not null,
  data_raw text,
  dcto text,
  operacao text,
  historico text,
  favorecido text,
  valor numeric(14,2) not null,
  saldo numeric(14,2),
  dedup_hash text not null,
  importado_em timestamptz not null default now()
);

create unique index if not exists uq_bs_cash_dedup
  on public.raw_bs_cash (dedup_hash);

create index if not exists raw_bs_cash_data_idx
  on public.raw_bs_cash (data_hora);

revoke all privileges on table public.raw_bs_cash from public, anon, authenticated;
grant select, insert, update, delete, references, trigger, truncate
  on table public.raw_bs_cash to service_role;
grant usage, select on sequence public.raw_bs_cash_id_seq to service_role;

insert into public.conta (nome, banco, unidade_id, ativa)
values ('BS Cash', 'BS Cash', (select id from public.unidade where nome = 'PRAIA'), true)
on conflict (nome) do nothing;

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
    case when e.movimentacao = 'Débito' then e.destino_documento else e.origem_documento end as contraparte_doc
  from raw_stone_extrato e

  union all

  select
    'bb'::text as origem,
    b.id as raw_id,
    'BB'::text as empresa,
    b.data as data_caixa,
    case when b.valor < 0 then 'Débito' else 'Crédito' end as movimentacao,
    b.lancamento as tipo,
    b.valor,
    trim(regexp_replace(coalesce(b.detalhes, b.lancamento), '^[0-9/ :.-]+', '')) as contraparte_nome,
    null::text as contraparte_doc
  from raw_bb b

  union all

  -- BS Cash: so a partir do corte ja usado para stone_extrato/bb, para nao
  -- duplicar o que o historico ja conta entre 2023 e 2025 (ver cabecalho).
  select
    'bs_cash'::text as origem,
    c.id as raw_id,
    'PRAIA'::text as empresa,
    c.data_hora::date as data_caixa,
    case when c.valor < 0 then 'Débito' else 'Crédito' end as movimentacao,
    c.operacao as tipo,
    c.valor,
    coalesce(nullif(c.favorecido, ''), c.operacao) as contraparte_nome,
    null::text as contraparte_doc
  from raw_bs_cash c
  where c.data_hora::date >= date '2026-01-01'
),
live_match as (
  select
    lb.origem, lb.raw_id, lb.empresa, lb.data_caixa, lb.movimentacao, lb.tipo, lb.valor,
    lb.contraparte_nome, lb.contraparte_doc,
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
      when lm.dp_cat = 'ANALISAR INDIVIDUAL' then null
      when lm.dp_cat is not null then lm.dp_cat
      when lm.origem = 'stone_extrato' and lm.movimentacao = 'Crédito' then
        case lm.tipo
          when 'Recebível de Cartão' then 'Recebível de Cartão'
          when 'Pix' then 'PIX'
          when 'TED' then 'TED'
          else 'Transação'
        end
      else null
    end as cat_final,
    case
      when lm.dp_cat = 'ANALISAR INDIVIDUAL' then 'analise'
      when lm.dp_cat is not null then 'classificado'
      when lm.origem = 'stone_extrato' and lm.movimentacao = 'Crédito' then 'classificado'
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
  (case when am.categoria is not null then cdo.dre_grupo else t.dre_grupo end)
    is distinct from 'CARTÃO DE CRÉDITO'
  and (case when am.categoria is not null then cdo.dre_grupo else t.dre_grupo end)
    is distinct from 'TRANSFERENCIA' as entra_dre
from tudo t
left join ajuste_manual am on am.origem = t.origem and am.raw_id = t.raw_id
left join categoria_dre cdo on cdo.categoria = am.categoria;

commit;
