-- =====================================================================
-- Reverte fato_financeiro para o estado anterior a 20260729
-- =====================================================================
--
-- PROBLEMA
--   20260729000000_historico_usa_de_para_quando_vazio.sql adicionou dois
--   LEFT JOIN com predicado baseado em funcao (so_digitos/normaliza_nome)
--   avaliados para cada linha de raw_historico (a maior tabela do sistema,
--   2023-2025) em toda consulta a fato_financeiro. Isso levou a paginas a
--   dar timeout ("canceling statement due to statement timeout").
--
-- ACAO
--   Restaura a view exatamente como estava em
--   20260726000000_classifica_bs_cash_e_corrige_transferencia.sql (historico
--   volta a usar so h.categoria/h.dre_grupo, sem lookup em de_para).
--
-- NAO REVERTIDO (nao tem relacao com a lentidao, ambos sao so UPDATE de
-- dado, sem custo de leitura):
--   - 20260727000000_limpa_categoria_invalida_historico.sql
--   - 20260728000000_classifica_bs_pagamento_historico.sql
--
-- PROXIMO PASSO (fora desta migration): resolver o objetivo original
-- ("liberar os ND para classificar") via UPDATE pontual em raw_historico
-- (copiando o resultado do de_para uma vez para as linhas hoje vazias),
-- em vez de um join dinamico a cada leitura da view.
-- =====================================================================

begin;

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
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Crédito' then 'Transferencia entre Contas'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Débito' and lm.tipo = 'PAGAMENTO DE REMUNERACAO' then 'Folha Salarial'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Débito' and lm.tipo = 'DEBITO SERVICO REMUNERACAO' then 'Tarifas Bancárias'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Débito' and lm.tipo = 'ESTORNO DE DEPOSITO' then 'Transferencia entre Contas'
      else null
    end as cat_final,
    case
      when lm.dp_cat = 'ANALISAR INDIVIDUAL' then 'analise'
      when lm.dp_cat is not null then 'classificado'
      when lm.origem = 'stone_extrato' and lm.movimentacao = 'Crédito' then 'classificado'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Crédito' then 'classificado'
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Débito'
       and lm.tipo in ('PAGAMENTO DE REMUNERACAO', 'DEBITO SERVICO REMUNERACAO', 'ESTORNO DE DEPOSITO') then 'classificado'
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
