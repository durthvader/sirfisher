-- =====================================================================
-- Marca de qual sistema (BB/Stone/Historico) vem cada excecao
-- =====================================================================
--
-- Pedido do usuario: nao era sobre o banco da contraparte (isso ja foi
-- feito nas migrations anteriores) e sim de qual extrato/sistema a
-- transacao foi importada - fato_financeiro.origem ('stone_extrato',
-- 'bb', 'historico'). analise_individual.html ja tinha essa coluna
-- disponivel (so nao mostrava); excecoes agrega por fornecedor e pode
-- ter mais de uma origem no mesmo grupo, entao vira lista.
-- =====================================================================

begin;

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
    coalesce(rse.destino_instituicao, rh.destino_instituicao) as destino_instituicao
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
  bool_or(
    exists (select 1 from public.conta c where origem_instituicao ilike '%' || c.banco || '%')
    and exists (select 1 from public.conta c where destino_instituicao ilike '%' || c.banco || '%')
  ) as tem_transferencia_propria,
  array_agg(distinct origem order by origem) as sistemas_origem
from detalhe
group by contraparte_nome, contraparte_doc,
  case when (contraparte_doc like '%/%' and contraparte_doc not like '%*%') then 'cnpj' else 'nome' end,
  case when (contraparte_doc like '%/%' and contraparte_doc not like '%*%') then so_digitos(contraparte_doc) else normaliza_nome(contraparte_nome) end
order by sum(valor);

create or replace view public.app_excecoes
with (security_barrier = true, security_invoker = false) as
select contraparte_nome, contraparte_doc, chave_tipo, chave_valor, qtd_lancamentos, total,
       natureza, data_min, data_max, tipos,
       origens_instituicao, destinos_instituicao, tem_transferencia_propria,
       sistemas_origem
from public.excecoes s
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

commit;
