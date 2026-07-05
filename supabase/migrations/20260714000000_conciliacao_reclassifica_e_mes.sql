-- =====================================================================
-- Conciliacao Stone: separa Pix/Voucher e adiciona referencia de mes
-- =====================================================================
--
-- Investigacao (leitura, antes desta migration) sobre por que existiam
-- tantos casos de "venda sem recebivel" (9.300) e "recebivel sem
-- venda" (1.782):
--
--   - 98% de "venda sem recebivel" (9.102 de 9.300) sao vendas
--     "Pix QRcode" (+110 Voucher). Pix na maquininha Stone cai na hora
--     e nunca gera parcela na agenda de recebiveis - nao e uma
--     divergencia, e a natureza do meio de pagamento. So ~80 casos
--     (majoritariamente Credito) sao lacunas reais.
--   - 88% de "recebivel sem venda" (1.567 de 1.782) sao parcelas de
--     vendas feitas em nov/dez de 2024, antes da janela de dados
--     comecar (raw_stone_vendas so tem dados a partir de jan/2025) -
--     limite de importacao, nao divergencia real.
--
-- Esta migration:
--   1. Cria a situacao 'sem recebivel esperado (pix/voucher)' para os
--      casos estruturais de Pix/Voucher, mantendo 'venda sem
--      recebivel' so para os casos reais (cartao).
--   2. Adiciona mes_referencia (coalesce da data da venda com o
--      primeiro vencimento do recebivel) e produto, para dar contexto
--      e permitir filtrar por mes na tela.
-- =====================================================================

begin;

create or replace view public.conciliacao_stone as
with v as (
  select
    stone_id,
    sum(valor_bruto) as bruto_venda,
    count(*) as n_venda,
    max(data_venda::date) as data_venda,
    max(produto) as produto
  from public.raw_stone_vendas
  where stone_id is not null
  group by stone_id
), r as (
  select
    stone_id,
    sum(valor_bruto) as bruto_receb,
    sum(valor_liquido) as liquido_receb,
    count(*) as n_parcelas,
    min(data_vencimento) as primeiro_venc,
    max(data_vencimento) as ultimo_venc,
    bool_or(categoria ilike '%cancelamento%') as tem_cancelamento
  from public.raw_stone_recebiveis
  where stone_id is not null
  group by stone_id
)
select
  coalesce(v.stone_id, r.stone_id) as stone_id,
  v.data_venda,
  v.bruto_venda,
  v.n_venda,
  r.bruto_receb,
  r.liquido_receb,
  r.n_parcelas,
  r.primeiro_venc,
  round((coalesce(v.bruto_venda, 0::numeric) - coalesce(r.bruto_receb, 0::numeric)), 2) as diferenca_bruto,
  case
    when coalesce(r.tem_cancelamento, false) then 'cancelado/estornado'
    when v.stone_id is null then 'recebível sem venda'
    when r.stone_id is null and v.produto in ('Pix QRcode', 'Voucher') then 'sem recebível esperado (Pix/Voucher)'
    when r.stone_id is null then 'venda sem recebível'
    when abs(coalesce(v.bruto_venda, 0::numeric) - coalesce(r.bruto_receb, 0::numeric)) > 0.01 then 'valor diverge'
    else 'ok'
  end as situacao,
  coalesce(v.data_venda, r.primeiro_venc) as mes_referencia,
  v.produto
from v full join r on v.stone_id = r.stone_id;

create or replace view public.app_conciliacao_stone
with (security_barrier = true, security_invoker = false) as
select stone_id, data_venda, bruto_venda, n_venda, bruto_receb, liquido_receb,
       n_parcelas, primeiro_venc, diferenca_bruto, situacao,
       mes_referencia, produto
from private.ler_conciliacao_stone();

-- Resumo pre-agregado por mes + situacao, para alimentar o seletor de
-- periodo e os cartoes/grafico sem precisar trazer as ~38 mil linhas
-- de conciliacao_stone para o navegador.
create or replace view public.conciliacao_stone_resumo_mensal as
select
  date_trunc('month', mes_referencia)::date as mes,
  to_char(date_trunc('month', mes_referencia), 'YYYY-MM') as ano_mes,
  situacao,
  count(*) as qtd,
  round(sum(coalesce(bruto_venda, 0::numeric)), 2) as total_venda,
  round(sum(coalesce(bruto_receb, 0::numeric)), 2) as total_recebivel
from public.conciliacao_stone
where mes_referencia is not null
group by 1, 2, 3
order by 1 desc;

create or replace view public.app_conciliacao_stone_resumo_mensal
with (security_barrier = true, security_invoker = false) as
select mes, ano_mes, situacao, qtd, total_venda, total_recebivel
from public.conciliacao_stone_resumo_mensal
where public.usuario_tem_papel(array['admin', 'socio']);

commit;
