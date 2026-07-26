-- =====================================================================
-- Vendas da Fundopay entram no faturamento
-- =====================================================================
--
-- PROBLEMA
--   O faturamento (venda_diaria) so conhece dois canais: raw_stone_vendas
--   e venda_especie. A maquininha Fundopay, usada de mai/2025 a mai/2026
--   em paralelo a Stone, nunca entrou -- suas vendas so apareciam quando o
--   dinheiro caia na conta Inter, ou seja, na camada de caixa/DRE.
--
--   Resultado: a DRE ja contava esses valores como receita (R$ 155.224,84
--   pelo extrato) e o planejamento nao, entao as duas telas discordavam
--   sobre quanto o restaurante vendeu. As metas de planejamento.html eram
--   comparadas a um realizado incompleto.
--
--   O usuario confirmou: era outra maquininha, as vendas NAO passavam pela
--   Stone. Logo o faturamento estava mesmo subestimado.
--
-- VALIDACAO DA FONTE (antes desta migration)
--   O arquivo de vendas da Fundopay fecha com o extrato da conta Inter:
--     vendas liquidas de MDR    R$ 177.780,77
--     recebido na conta Inter   R$ 177.747,35
--     diferenca                 R$      33,42  (0,02%, vendas de mai/2026
--                                               liquidadas apos o extrato)
--   Os dois terminais (6R867578 e 6R867564) estao no arquivo, nao ha
--   antecipacao e os 1.897 "ID Venda" sao unicos.
--
-- SOLUCAO
--   + raw_fundopay_vendas, no mesmo padrao de raw_stone_vendas.
--   ~ venda_diaria ganha um terceiro braco com as vendas APROVADAS, pela
--     data real da venda e pelo valor BRUTO -- exatamente os criterios ja
--     usados para a Stone, para nao misturar bases.
--
--   Situacao: o arquivo traz Aprovada (1.796), Negada (98) e Desfeita (3).
--   A tabela guarda todas -- a decisao fica auditavel e reversivel -- e o
--   filtro vive na view. Negada e cartao recusado: nao houve venda, e
--   contar infla o faturamento. Desfeita e operacao cancelada.
--
--   O braco conta 1 em qtd (como a Stone), entao ticket medio e quantidade
--   de vendas passam a considerar a Fundopay. venda_especie segue com 0,
--   como ja era.
--
-- OBJETOS
--   + public.raw_fundopay_vendas (+ indices, RLS, grants service_role)
--   ~ public.venda_diaria (create or replace view; mesmas colunas)
--
-- EFEITO EM CASCATA (leem venda_diaria; nenhuma alterada aqui)
--   painel_meta_real_mensal (planejamento.html), projecao_venda_diaria e,
--   por ela, recebimento_projetado / projecao_despesa_direta / caixa /
--   calendario; painel_diario, tendencia_mes, peso_mensal, vendas.html.
--
-- RISCO: medio. O faturamento sobe ~R$ 181 mil distribuidos em 13 meses
--   (maiores: ago/2025 +31,0 mil; set +28,9 mil; out +26,5 mil), entao
--   percentuais de meta ja publicados mudam -- para melhor, corrigindo uma
--   subestimativa. A DRE NAO muda: ela ja contava esses valores pelo
--   extrato, e esta migration justamente elimina a divergencia entre as
--   duas telas. Nenhum lancamento financeiro e alterado.
--
-- OBSERVACAO
--   As regras de recebimento (recebimento_regra: credito 48,7%/30d,
--   debito 27,8%/1d, pix 23,5%) foram calibradas com o mix da Stone. Com a
--   Fundopay no faturamento o mix real muda um pouco; a projecao futura
--   segue funcionando, mas vale recalibrar depois com a base completa.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. raw_fundopay_vendas
-- ---------------------------------------------------------------------
-- O numero do cartao vem mascarado no arquivo e nao e guardado: nao e
-- necessario para faturamento e e dado de meio de pagamento.
create table if not exists public.raw_fundopay_vendas (
  id bigserial primary key,
  id_venda text not null,
  data_venda timestamptz not null,
  bandeira text,
  n_parcelas integer,
  modalidade text,
  valor_venda numeric(14,2) not null,
  mdr numeric(14,2),
  antecipacao numeric(14,2),
  valor_liquido numeric(14,2),
  tipo_terminal text,
  terminal text,
  data_confirmacao timestamptz,
  situacao text not null,
  dedup_hash text not null,
  importado_em timestamptz not null default now()
);

create unique index if not exists uq_fundopay_vendas_dedup
  on public.raw_fundopay_vendas (dedup_hash);

create index if not exists raw_fundopay_vendas_data_idx
  on public.raw_fundopay_vendas (data_venda);

create index if not exists raw_fundopay_vendas_situacao_idx
  on public.raw_fundopay_vendas (situacao);

alter table public.raw_fundopay_vendas enable row level security;

revoke all privileges on table public.raw_fundopay_vendas
  from public, anon, authenticated;
grant select, insert, update, delete, references, trigger, truncate
  on table public.raw_fundopay_vendas to service_role;
grant usage, select on sequence public.raw_fundopay_vendas_id_seq to service_role;

comment on table public.raw_fundopay_vendas is
  'Vendas da maquininha Fundopay (mai/2025 a mai/2026), canal paralelo a Stone. Carga por 07_importar_fundopay.py; so as Aprovadas entram em venda_diaria.';

-- ---------------------------------------------------------------------
-- 2. venda_diaria com o terceiro canal
-- ---------------------------------------------------------------------
create or replace view public.venda_diaria as
select
  dia,
  sum(bruto) as bruto,
  sum(qtd) as qtd_vendas
from (
  select
    v.data_venda::date as dia,
    v.valor_bruto - coalesce(c.cancelado, 0::numeric) as bruto,
    1 as qtd
  from public.raw_stone_vendas v
  left join (
    select r.stone_id, sum(abs(r.valor_bruto)) as cancelado
    from public.raw_stone_recebiveis r
    where r.categoria ilike '%cancelamento%'
    group by r.stone_id
  ) c on c.stone_id = v.stone_id
  where v.data_venda is not null

  union all

  select e.data as dia, e.valor as bruto, 0 as qtd
  from public.venda_especie e

  union all

  -- Fundopay: mesma regra da Stone -- data real da venda e valor bruto.
  -- Negada (cartao recusado) e Desfeita (cancelada) nao sao venda.
  select
    f.data_venda::date as dia,
    f.valor_venda::numeric as bruto,
    1 as qtd
  from public.raw_fundopay_vendas f
  where lower(btrim(f.situacao)) = 'aprovada'
) x
group by dia;

comment on view public.venda_diaria is
  'Faturamento diario: Stone (liquido de cancelamento), dinheiro em especie e Fundopay aprovada. Sempre pela data da venda e pelo valor bruto.';

commit;
