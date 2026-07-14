-- =====================================================================
-- entra_dre passa a excluir o grupo CONTABIL (nao so a categoria antiga
-- "TRANSFERENCIA" do historico) -- do lado da receita e da despesa
-- =====================================================================
--
-- PROBLEMA
--   fato_financeiro.entra_dre so excluia dre_grupo = 'TRANSFERENCIA'
--   (nome de categoria usado no historico legado). O grupo CONTABIL --
--   que reune "Transferencia entre Contas", "Antecipacao de Receita",
--   "ANALISAR INDIVIDUAL", "estornado" e "pagamento devolvido" -- nunca
--   foi excluido de forma geral. mv_despesa_mensal ja excluia CONTABIL
--   do lado da despesa (por isso o bug nao aparecia la); a migration
--   20260739000000_calendario_exclui_contabil.sql tratou o mesmo buraco
--   so para despesas_reais e listar_despesas_dia (calendario.html).
--
--   O lado da RECEITA nunca foi corrigido. Exemplo real (jul/2026):
--   2 lancamentos de "Transferencia entre Contas" (BB e BS Cash, dinheiro
--   movendo entre contas da propria empresa) somavam R$ 29.708,67
--   contados como Receita -- inflando receita, lucro bruto, lucro
--   liquido e resultado da DRE em index.html e dre.html. Nao e caso
--   isolado: todo mes de 2026 teve entre R$ 27 mil e R$ 38 mil de
--   "Receita" vindos de CONTABIL (conferido jan-jul/2026 antes desta
--   migration, somente leitura).
--
-- SOLUCAO
--   Recriar fato_financeiro acrescentando a exclusao de 'CONTABIL' ao
--   calculo de entra_dre, MANTENDO a exclusao ja existente de
--   'TRANSFERENCIA' -- confirmado que sao grupos distintos:
--   'TRANSFERENCIA' cobre a categoria "Deposito Dinheiro" (58
--   lancamentos, R$ 39.064,00, set/2025 a jun/2026, ja corretamente
--   excluidos hoje) e 'CONTABIL' cobre 5 categorias.
--
--   Dentro de CONTABIL, uma categoria e tratada diferente das demais:
--   'ANALISAR INDIVIDUAL' (R$ 462 mil em despesa, 134 lancamentos,
--   2022-2025) significa "nunca foi classificado de verdade" -- boa
--   parte e Pix para a propria empresa/coligadas e para os socios.
--   NAO ha confirmacao de que sejam movimentos nao-operacionais; excluir
--   em bloco decidiria, sem base, que nao sao despesa. Por isso essa
--   categoria fica de fora desta correcao (continua entrando na DRE
--   exatamente como hoje) -- e fica registrada como pendencia separada
--   de classificacao manual (ver docs/CANAL_IA.md).
--
--   As outras 4 categorias de CONTABIL sao movimentos nao-operacionais
--   confirmados: "Transferencia entre Contas" (autotransferencia entre
--   contas da propria empresa), "estornado" (estornos, os dois lados se
--   cancelam quase por completo), "Antecipacao de Receita" (operacao
--   financeira sobre recebivel ja contado em outro lugar, nao venda
--   nova) e "pagamento devolvido". Essas sim sao excluidas.
--
--   Nenhuma outra parte da view muda -- inclusive mantem o ajuste
--   TEMPORARIO do cartao de credito (20260738000000, ainda com rollback
--   pendente, ver docs/CANAL_IA.md).
--
-- OBJETOS AFETADOS
--   ~ fato_financeiro (create or replace view; mesmas colunas e tipos)
--
-- EFEITO EM CASCATA (sem alteracao direta; leem fato_financeiro):
--   painel_resumo_mensal, painel_dre_cascata, painel_composicao_despesa,
--   painel_margem_contribuicao, calendario financeiro, excecoes, e
--   qualquer view/RPC que filtre por entra_dre. Corrige retroativamente
--   toda a serie historica de 2026 (e os meses de 2025 com o mesmo
--   padrao), pois fato_financeiro nao e materializada.
--
-- RISCO: medio -- muda numeros ja publicados da DRE em varios meses
--   (reduz receita reportada, corrigindo uma superestimativa). Sem
--   mudanca de schema; create or replace aceito. Sem dado alterado,
--   so a regra de inclusao na DRE.
-- =====================================================================

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
      -- entrando na DRE exatamente como antes desta migration.
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
