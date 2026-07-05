-- =====================================================================
-- Mais contexto por transacao em Analise individual e Classificar excecoes
-- =====================================================================
--
-- Pedido do usuario: entender melhor cada lancamento (ex.: uma
-- transacao com contraparte "Sir Fisher" pode ser transferencia entre
-- contas proprias, mas hoje nao da pra saber pra onde foi).
--
-- fato_financeiro tem 3 origens (stone_extrato, bb, historico), cada
-- uma batendo com uma tabela bruta diferente (raw_stone_extrato,
-- raw_bb, raw_historico respectivamente - confirmado comparando valor
-- linha a linha antes de escrever esta migration). So raw_stone_extrato
-- e raw_historico tem colunas de instituicao origem/destino; raw_bb so
-- tem lancamento/detalhes em texto livre.
--
-- analise_individual (por transacao) ganha:
--   - tipo: ja existe em fato_financeiro, so nao era selecionado.
--   - origem_instituicao / destino_instituicao: de qual banco saiu e
--     para qual foi, quando a origem da transacao permite saber.
--   - descricao: texto livre do extrato do BB (lancamento + detalhes),
--     unico caso em que isso existe de forma util.
--   - transferencia_propria: true quando origem E destino batem com
--     uma conta cadastrada em public.conta (Stone, Banco do Brasil,
--     BTG, Banco do Nordeste, Banco Inter) - sinaliza transferencia
--     entre contas da propria empresa.
--
-- excecoes (agregado por fornecedor novo) ganha:
--   - tipos: lista dos tipos de lancamento distintos daquele grupo
--     (ex. "Pix, TED"), para dar contexto na hora de definir a
--     categoria do fornecedor.
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
    exists (
      select 1 from public.conta c
      where coalesce(rse.origem_instituicao, rh.origem_instituicao) ilike '%' || c.banco || '%'
    )
    and exists (
      select 1 from public.conta c
      where coalesce(rse.destino_instituicao, rh.destino_instituicao) ilike '%' || c.banco || '%'
    )
  ) as transferencia_propria
from public.fato_financeiro f
left join public.raw_stone_extrato rse on f.origem = 'stone_extrato' and rse.id = f.raw_id
left join public.raw_historico rh on f.origem = 'historico' and rh.id = f.raw_id
left join public.raw_bb rb on f.origem = 'bb' and rb.id = f.raw_id
where f.status = 'analise'
order by abs(f.valor) desc, f.data_caixa desc;

create or replace view public.excecoes as
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
  array_agg(distinct tipo order by tipo) filter (where tipo is not null) as tipos
from public.fato_financeiro
where status = 'excecao'
group by contraparte_nome, contraparte_doc,
  case when (contraparte_doc like '%/%' and contraparte_doc not like '%*%') then 'cnpj' else 'nome' end,
  case when (contraparte_doc like '%/%' and contraparte_doc not like '%*%') then so_digitos(contraparte_doc) else normaliza_nome(contraparte_nome) end
order by sum(valor);

create or replace view public.app_analise_individual
with (security_barrier = true, security_invoker = false) as
select origem, raw_id, empresa, unidade, data_caixa, movimentacao, natureza, valor,
       contraparte_nome, contraparte_doc, fornecedor,
       tipo, origem_instituicao, destino_instituicao, descricao, transferencia_propria
from public.analise_individual s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

create or replace view public.app_excecoes
with (security_barrier = true, security_invoker = false) as
select contraparte_nome, contraparte_doc, chave_tipo, chave_valor, qtd_lancamentos, total,
       natureza, data_min, data_max, tipos
from public.excecoes s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

commit;
