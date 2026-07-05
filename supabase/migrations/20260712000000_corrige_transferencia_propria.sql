-- =====================================================================
-- Corrige o selo "transferencia entre contas" para usar documento, nao banco
-- =====================================================================
--
-- Bug reportado pelo usuario: o selo acendia para pagamentos comuns a
-- pessoas fisicas (ex: "JOSEFA CLEIDE DE JESUS SILVA") so porque o
-- destino era "Banco do Brasil S.A." - um banco enorme, usado por
-- qualquer pessoa, nao so pela empresa. A regra anterior comparava o
-- NOME da instituicao contra a tabela conta (Stone/BB/BTG/BNB/Inter),
-- o que da falso positivo sempre que o destinatario comum tambem
-- bancar num desses bancos.
--
-- Correcao: origem_documento e destino_documento (CPF/CNPJ do titular
-- de cada lado, ja disponiveis em raw_stone_extrato/raw_historico) sao
-- muito mais confiaveis - se os dois lados tem o MESMO documento, so
-- pode ser transferencia entre contas do mesmo titular (a empresa,
-- ja que e o extrato bancario dela). Confirmado contra dados reais:
--   - Sir Fisher Stone -> Banco do Nordeste (raw_id 10487): origem_doc
--     = destino_doc = 37.889.047/0001-68 (CNPJ da empresa) -> correto
--     continuar marcando como propria.
--   - Empresa -> Josefa Cleide (Stone -> BB pessoal dela): origem_doc
--     = CNPJ da empresa, destino_doc = CPF da Josefa (documentos
--     diferentes) -> corrigido para NAO marcar mais como propria.
--
-- Nao depende mais da tabela conta para este calculo.
-- =====================================================================

begin;

create or replace view public.analise_individual as
select
  f.origem,
  f.raw_id,
  f.empresa,
  f.unidade,
  f.data_caixa,
  f.movimentacao,
  f.natureza,
  f.valor,
  f.contraparte_nome,
  f.contraparte_doc,
  f.fornecedor,
  f.tipo,
  coalesce(rse.origem_instituicao, rh.origem_instituicao) as origem_instituicao,
  coalesce(rse.destino_instituicao, rh.destino_instituicao) as destino_instituicao,
  case when f.origem = 'bb'
    then nullif(trim(both ' - ' from concat_ws(' - ', rb.lancamento, nullif(rb.detalhes, ''))), '')
  end as descricao,
  (
    coalesce(rse.origem_documento, rh.origem_documento) is not null
    and coalesce(rse.origem_documento, rh.origem_documento) = coalesce(rse.destino_documento, rh.destino_documento)
  ) as transferencia_propria
from public.fato_financeiro f
left join public.raw_stone_extrato rse on f.origem = 'stone_extrato' and rse.id = f.raw_id
left join public.raw_historico rh on f.origem = 'historico' and rh.id = f.raw_id
left join public.raw_bb rb on f.origem = 'bb' and rb.id = f.raw_id
where f.status = 'analise'
order by abs(f.valor) desc, f.data_caixa desc;

create or replace view public.excecoes as
with detalhe as (
  select
    f.origem,
    f.contraparte_nome,
    f.contraparte_doc,
    f.valor,
    f.data_caixa,
    f.tipo,
    coalesce(rse.origem_instituicao, rh.origem_instituicao) as origem_instituicao,
    coalesce(rse.destino_instituicao, rh.destino_instituicao) as destino_instituicao,
    coalesce(rse.origem_documento, rh.origem_documento) as origem_documento,
    coalesce(rse.destino_documento, rh.destino_documento) as destino_documento
  from public.fato_financeiro f
  left join public.raw_stone_extrato rse on f.origem = 'stone_extrato' and rse.id = f.raw_id
  left join public.raw_historico rh on f.origem = 'historico' and rh.id = f.raw_id
  where f.status = 'excecao'
)
select
  contraparte_nome,
  contraparte_doc,
  case
    when (contraparte_doc like '%/%' and contraparte_doc not like '%*%') then 'cnpj'
    else 'nome'
  end as chave_tipo,
  case
    when (contraparte_doc like '%/%' and contraparte_doc not like '%*%') then so_digitos(contraparte_doc)
    else normaliza_nome(contraparte_nome)
  end as chave_valor,
  count(*) as qtd_lancamentos,
  sum(valor) as total,
  case when sum(valor) >= 0 then 'Receita' else 'Despesa' end as natureza,
  min(data_caixa) as data_min,
  max(data_caixa) as data_max,
  array_agg(distinct tipo order by tipo) filter (where tipo is not null) as tipos,
  array_agg(distinct origem_instituicao order by origem_instituicao) filter (where origem_instituicao is not null) as origens_instituicao,
  array_agg(distinct destino_instituicao order by destino_instituicao) filter (where destino_instituicao is not null) as destinos_instituicao,
  bool_or(origem_documento is not null and origem_documento = destino_documento) as tem_transferencia_propria,
  array_agg(distinct origem order by origem) as sistemas_origem
from detalhe
group by contraparte_nome, contraparte_doc,
  case when (contraparte_doc like '%/%' and contraparte_doc not like '%*%') then 'cnpj' else 'nome' end,
  case when (contraparte_doc like '%/%' and contraparte_doc not like '%*%') then so_digitos(contraparte_doc) else normaliza_nome(contraparte_nome) end
order by sum(valor);

commit;
