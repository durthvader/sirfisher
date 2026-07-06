-- =====================================================================
-- Resolve, uma unica vez, o historico sem categoria via DE-Para
-- =====================================================================
--
-- CONTEXTO
--   20260729 tentou resolver isso com um JOIN dinamico dentro da view
--   fato_financeiro (custo em toda leitura, para a tabela toda de
--   raw_historico) e causou timeout nas paginas. Revertido em 20260730.
--
--   Esta migration faz o mesmo lookup (de_para por cnpj, com fallback por
--   nome, mesma normalizacao/precedencia do restante do sistema), mas como
--   UPDATE pontual, uma vez, e SO nas linhas que hoje estao com categoria
--   nula (~325 linhas, nao a tabela inteira). Zero custo nas leituras da
--   view dai em diante -- o resultado fica gravado na propria linha, igual
--   ao restante do historico ja congelado.
--
-- ESCOPO / LIMITACAO
--   Linhas cujo de_para aponte para a categoria magica 'ANALISAR
--   INDIVIDUAL' NAO sao alteradas aqui -- raw_historico nao tem coluna de
--   status para representar o fluxo de analise_individual.html, entao
--   ficam de fora (continuam em excecao) ate uma decisao separada.
--
--   Este UPDATE reflete o de_para de HOJE. Fornecedores classificados
--   depois disso, em classificar_excecoes.html, NAO reclassificam
--   automaticamente o historico (a view nao consulta de_para para
--   historico) -- para pegar classificacoes futuras, esta migration
--   precisaria ser reexecutada manualmente sobre as linhas ainda vazias.
--
-- RISCO: baixo. So afeta linhas hoje com categoria is null; nenhuma linha
-- ja classificada e tocada.
-- =====================================================================

with de_para_ativo as (
  select distinct on (chave_tipo, chave_valor)
    chave_tipo, chave_valor, categoria, fornecedor
  from public.de_para
  where ativo
  order by chave_tipo, chave_valor, id desc
),
candidatos as (
  select
    h.id,
    case when h.movimentacao = 'Débito' then h.destino_documento else h.origem_documento end as contraparte_doc,
    case when h.movimentacao = 'Débito' then h.destino else h.origem end as contraparte_nome
  from public.raw_historico h
  where h.categoria is null
),
resolvido as (
  select
    c.id,
    coalesce(dpc.categoria, dpn.categoria) as categoria,
    coalesce(dpc.fornecedor, dpn.fornecedor) as fornecedor
  from candidatos c
  left join de_para_ativo dpc
    on dpc.chave_tipo = 'cnpj'
   and dpc.chave_valor = case
     when c.contraparte_doc like '%/%' and c.contraparte_doc not like '%*%' then so_digitos(c.contraparte_doc)
     else null
   end
  left join de_para_ativo dpn
    on dpn.chave_tipo = 'nome'
   and dpn.chave_valor = case
     when c.contraparte_nome ilike 'desconhecido' then null
     else normaliza_nome(c.contraparte_nome)
   end
  where coalesce(dpc.categoria, dpn.categoria) is not null
    and coalesce(dpc.categoria, dpn.categoria) <> 'ANALISAR INDIVIDUAL'
)
update public.raw_historico rh
set categoria = r.categoria,
    dre_grupo = cd.dre_grupo,
    fornecedor = coalesce(rh.fornecedor, r.fornecedor)
from resolvido r
left join public.categoria_dre cd on cd.categoria = r.categoria
where rh.id = r.id;
