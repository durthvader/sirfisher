-- =====================================================================
-- Classificacao automatica do BS Cash + corrige regra de transferencia
-- =====================================================================
--
-- PROBLEMA 1 (regra existente incorreta)
--   de_para ja tem uma regra (id 1660, cnpj 40994589000105 = CNPJ do BS
--   Cash) que classifica qualquer debito de Stone/BB para essa conta como
--   'Folha Salarial'. Isso conta a TRANSFERENCIA DE FUNDO (Stone/BB -> BS
--   Cash) como se fosse a despesa em si. Confirmado com dado real: Stone
--   debitou R$6.500 e R$20.000 em 04/01/2026 (ja classificados Folha
--   Salarial via essa regra) e o BS Cash recebeu exatamente R$6.500 e
--   R$20.000 em 05/01/2026 - mesma transferencia, ja contada do lado
--   errado. Se nao corrigirmos, ao classificar as saidas do BS Cash para
--   funcionarios (abaixo) essa mesma folha seria contada 2x.
--
-- PROBLEMA 2 (BS Cash sem classificacao automatica)
--   Toda transacao do BS Cash cai em "excecao" (precisa classificar uma a
--   uma em classificar_excecoes.html), mas o padrao e previsivel:
--     - Creditos (960 linhas): 100% sao a propria empresa transferindo
--       fundo para o BS Cash (PIX da "SIR FISHER COMERCIO...", depositos
--       com historico "TRANSFERENCIA DE SALDO", etc.) -> sempre
--       Transferencia entre Contas.
--     - Debito "PAGAMENTO DE REMUNERACAO" (789 linhas, 100% com
--       favorecido em formato de CPF mascarado) -> Folha Salarial.
--     - Debito "DEBITO SERVICO REMUNERACAO" (16 linhas) -> e taxa do
--       banco pelo processamento da folha, nao a folha em si -> Tarifas
--       Bancarias.
--     - Debito "ESTORNO DE DEPOSITO" (1 linha) -> estorno de um credito
--       que era transferencia -> Transferencia entre Contas tambem.
--
-- SOLUCAO
--   1) UPDATE na linha existente de de_para (id 1660) para o cnpj do BS
--      Cash, trocando categoria para 'Transferencia entre Contas'. de_para
--      tem constraint UNIQUE (chave_tipo, chave_valor) - so existe uma
--      linha ativa por chave, entao e UPDATE, nao INSERT (a ordenacao por
--      "id desc" na view e defensiva, nao um mecanismo de versionamento).
--   2) fato_financeiro (create or replace view) ganha novos ramos no
--      mesmo mecanismo ja usado para classificar credito do stone_extrato
--      automaticamente (live_cat/cat_final), agora tambem para bs_cash.
--
-- ESCOPO / NAO INCLUIDO
--   raw_historico (2023-2025) tem seu proprio grupo de linhas referenciando
--   o cnpj do BS Cash, com categorias MISTURADAS (Folha Salarial, #N/A,
--   PIX, Sistemas, Transacao, estornado) - nao e so trocar uma regra, e
--   editar dado bruto congelado linha a linha. Fora de escopo aqui;
--   decisao separada do usuario.
--
-- RISCO: baixo.
--   - de_para: so INSERT (nenhuma linha e apagada/alterada).
--   - fato_financeiro: mesmas colunas de saida; so acrescenta condicoes
--     ao CASE existente (mesmo padrao ja usado para stone_extrato).
-- =====================================================================

begin;

update public.de_para
set categoria = 'Transferencia entre Contas', atualizado_em = now()
where chave_tipo = 'cnpj' and chave_valor = '40994589000105';

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
      -- BS Cash: creditos sao sempre fundo transferido de outra conta
      -- propria (confirmado: 100% dos creditos do arquivo importado sao
      -- da propria empresa ou tem historico "TRANSFERENCIA DE SALDO").
      when lm.origem = 'bs_cash' and lm.movimentacao = 'Crédito' then 'Transferencia entre Contas'
      -- BS Cash: debitos tem 3 tipos conhecidos no arquivo importado.
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
