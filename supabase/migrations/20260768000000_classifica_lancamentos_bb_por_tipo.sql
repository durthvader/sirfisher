-- =====================================================================
-- Classifica lancamentos do BB pelo tipo, como ja e feito para Stone,
-- BS Cash e Inter
-- =====================================================================
--
-- PROBLEMA
--   O braco 'bb' do fato_financeiro nao tem regra por tipo de lancamento.
--   Sobra so o de_para por nome da contraparte -- e o nome, num extrato de
--   BB, e quem pagou. Resultado: o MESMO tipo de lancamento cai em duas
--   situacoes diferentes conforme o pagador ja seja conhecido ou nao:
--
--     Pix-Recebido QR Code       57 classificados (PIX)  x  73 excecoes
--     Tarifa Pix Recebido        19 classificados        x  14 excecoes
--     Tarifa Pacote de Servicos   6 classificados        x   6 excecoes
--
--   Os 73 "Pix-Recebido QR Code" em excecao sao vendas por QR Code pagas
--   por clientes (pessoas fisicas, ticket medio R$ 33,62, R$ 2.454,00 no
--   total). Cada cliente novo vira uma excecao nova, entao a fila de
--   classificar_excecoes.html cresce sozinha a cada importacao -- sem que
--   haja qualquer decisao real a tomar.
--
-- SOLUCAO
--   Regras por tipo para o braco 'bb', na mesma posicao das regras que ja
--   existem para stone_extrato, bs_cash e inter -- ou seja, DEPOIS do
--   de_para, que continua tendo precedencia. Nada do que hoje esta
--   classificado muda de categoria; as regras so alcancam o que hoje cai
--   em excecao.
--
--     Pix-Recebido QR Code                      -> PIX (RECEITAS)
--     Tarifa Pix Recebido                       -> Tarifas Bancarias
--     Tarifa Pacote de Servicos                 -> Tarifas Bancarias
--     Cobranca de I.O.F.                        -> Tarifas Bancarias
--     Cobranca de Juros                         -> Tarifas Bancarias
--     Pix-Envio devolvido                       -> pagamento devolvido
--     Pix-Recebimento devolvido                 -> pagamento devolvido
--
--   "PIX" (e nao "Transacao", rotulo que a Stone usa para QR Code) para
--   ficar igual aos 57 lancamentos do proprio BB que o de_para ja
--   classificou assim -- o mesmo tipo de lancamento nao pode aparecer com
--   dois rotulos. As duas categorias sao RECEITAS, entao o efeito na DRE e
--   identico de qualquer forma.
--
--   "pagamento devolvido" e CONTABIL, ja excluido da DRE pela
--   20260748000000, que e o tratamento correto para estorno.
--
-- FICAM DE FORA, de proposito (exigem decisao caso a caso, e cada um tem
-- historico de ser classificado individualmente):
--   Pix - Enviado (2 excecoes), Pagamento de Boleto (1), Pagamento de
--   Impostos (1). Os boletos ja classificados viraram Aluguel, Gas e Plano
--   Dentario -- ou seja, o tipo nao determina a categoria.
--   Tambem nao sao tocados: Dep dinheiro ATM/inter ag (ja em Deposito
--   Dinheiro), BB GIRO PRONAMPE, BB RF LP Selic, Pagamento de Telefone,
--   Pix - Recebido e Pix - Rejeitado, todos ja classificados hoje.
--
-- EFEITO
--   96 das 100 excecoes atuais do BB saem da fila. Mais importante: novas
--   importacoes de extrato BB param de gerar excecao para venda por QR
--   Code e para tarifa. Receita reconhecida sobe R$ 2.454,00 (vendas que
--   estavam paradas sem categoria) e despesa sobe R$ 491,13 em tarifas,
--   ambas espalhadas entre jul e dez/2025.
--
-- OBJETOS
--   ~ public.fato_financeiro (create or replace view; mesmas colunas)
--
-- RISCO: baixo. Sem mudanca de schema. O de_para mantem precedencia, entao
--   nenhuma classificacao existente e sobrescrita. Reversivel: remover os
--   tres blocos "when lm.origem = 'bb'".
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
    i.valor::numeric(14,2) as valor,
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
      -- BB por tipo de lancamento: o nome da contraparte e o cliente que
      -- pagou, entao sem estas regras cada pagador novo vira excecao.
      when lm.origem = 'bb' and lm.tipo = 'Pix-Recebido QR Code' then 'PIX'
      when lm.origem = 'bb' and lm.tipo in (
        'Tarifa Pix Recebido', 'Tarifa Pacote de Serviços',
        'Cobrança de I.O.F.', 'Cobrança de Juros'
      ) then 'Tarifas Bancárias'
      when lm.origem = 'bb' and lm.tipo in (
        'Pix-Envio devolvido', 'Pix-Recebimento devolvido'
      ) then 'pagamento devolvido'
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
      when lm.origem = 'bb' and lm.tipo in (
        'Pix-Recebido QR Code', 'Tarifa Pix Recebido', 'Tarifa Pacote de Serviços',
        'Cobrança de I.O.F.', 'Cobrança de Juros',
        'Pix-Envio devolvido', 'Pix-Recebimento devolvido'
      ) then 'classificado'
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
