-- =====================================================================
-- Faturamento passa a contar apenas o estabelecimento da Praia
-- =====================================================================
--
-- PROBLEMA
--   O painel e da unidade PRAIA, mas em 28/06/2026 (03:13) uma sessao de
--   importacao subiu tambem os relatorios de vendas da Imprensa e do PUB.
--   O `venda_diaria` nao tem nocao de estabelecimento, entao essas vendas
--   passaram a contar como faturamento da Praia:
--
--     mes        faturamento   de outras casas
--     2025-12     165.378,72        1.500,00   (stonecode 173835323)
--     2026-01     224.459,33        7.497,17
--     2026-02     133.982,29        4.809,05
--     2026-03     141.478,52        4.653,55
--     2026-04     131.098,01        3.846,17
--     2026-05     165.302,31        2.830,00
--
--   Total R$ 25.135,94 -- ate 3,6% do mes.
--
--   Os tres estabelecimentos (informados pelo usuario):
--     770398216 -> PRAIA      (o painel)
--     140366173 -> IMPRENSA
--     916046432 -> PUB
--
-- POR QUE FICOU INVISIVEL
--   As linhas de Pix QRcode **nao trazem stonecode** no relatorio da
--   Stone -- so as de cartao trazem. Entao filtrar por stonecode sozinho
--   deixaria passar o Pix das outras casas (111 transacoes).
--
--   A saida e o **numero de serie do terminal**: conferido na base, cada
--   serie pertence a um unico stonecode, nenhuma migrou entre unidades.
--   Como o Pix e a venda de cartao saem do mesmo terminal, a serie
--   identifica a unidade mesmo quando o stonecode vem vazio.
--
-- SOLUCAO
--   + `stone_estabelecimento`: mapa stonecode -> unidade, explicito e
--     consultavel, em vez de espalhar o codigo da Praia pelas views.
--   ~ `recebimento_stone_net` passa a **excluir** as linhas cujo
--     estabelecimento resolvido (por stonecode ou por serie do terminal)
--     seja de outra unidade.
--   ~ `venda_diaria` deixa de repetir o calculo do liquido de cancelamento
--     e passa a ler o `recebimento_stone_net`. As duas expressoes eram
--     identicas; agora o filtro de unidade vale para os dois caminhos do
--     faturamento por construcao, sem risco de um divergir do outro
--     (foi exatamente o que aconteceu na 20260777000000).
--
--   O filtro e por **exclusao do que se sabe ser de outra casa**, nao por
--   inclusao so do que se sabe ser Praia. Assim um terminal novo da Praia
--   continua contando desde o primeiro dia, mesmo antes de aparecer no
--   mapa. O risco oposto -- um estabelecimento novo nao cadastrado entrar
--   calado -- fica coberto pelo aviso no importador.
--
-- NAO E AFETADO
--   - Caixa e DRE: `raw_stone_extrato` tem uma conta so (a Stone da
--     Praia), entao o dinheiro das outras casas nunca passou por ali.
--   - Cancelamentos: os 7 existentes sao todos do 770398216.
--   - `conciliacao_stone` continua lendo as tabelas cruas de proposito --
--     ela serve para auditar a carga, e esconder linha atrapalharia.
--
-- OBJETOS
--   + public.stone_estabelecimento (tabela + seed idempotente)
--   ~ public.recebimento_stone_net (create or replace, mesmas colunas)
--   ~ public.venda_diaria          (create or replace, mesmas colunas)
--
--   Os 30 objetos que dependem dessas duas views (ate `mv_fluxo_caixa_diario`
--   e `app_painel_fluxo_caixa`, no 6o nivel) seguem validos: `create or
--   replace` preserva nome, ordem e tipo das colunas.
--
-- RISCO: medio -- o faturamento historico de 6 meses muda (para menos, e
--   para o valor correto). Caixa, DRE e saldos nao mudam.
-- =====================================================================

create table if not exists public.stone_estabelecimento (
  stonecode text primary key,
  unidade   text not null,
  descricao text,
  criado_em timestamptz not null default now()
);

comment on table public.stone_estabelecimento is
  'Mapa stonecode -> unidade operacional. O painel cobre a PRAIA; as demais entram aqui para serem excluidas do faturamento. Linhas de Pix nao trazem stonecode, por isso a resolucao usa tambem o numero de serie do terminal.';

insert into public.stone_estabelecimento (stonecode, unidade, descricao) values
  ('770398216', 'PRAIA',    'Sir Fisher Praia -- unidade do painel'),
  ('140366173', 'IMPRENSA', 'Sir Fisher Imprensa'),
  ('916046432', 'PUB',      'Sir Fisher PUB')
on conflict (stonecode) do update
  set unidade = excluded.unidade,
      descricao = excluded.descricao;

revoke all on public.stone_estabelecimento from anon, authenticated;

-- ---------------------------------------------------------------------
-- Vendas Stone da Praia, liquidas de cancelamento
-- ---------------------------------------------------------------------
create or replace view public.recebimento_stone_net as
with mapa_terminal as (
  -- Cada serie pertence a um unico stonecode (conferido na base). As
  -- vendas de cartao trazem o stonecode; o Pix do mesmo terminal, nao.
  select n_serie, min(stonecode) as stonecode
  from public.raw_stone_vendas
  where stonecode is not null
    and n_serie is not null
  group by n_serie
), cancelado as (
  select r.stone_id, sum(abs(r.valor_bruto)) as cancelado
  from public.raw_stone_recebiveis r
  where r.categoria ilike '%cancelamento%'
  group by r.stone_id
)
select
  v.id,
  v.data_venda,
  v.produto,
  v.bandeira,
  v.valor_bruto - coalesce(c.cancelado, 0::numeric) as bruto_net
from public.raw_stone_vendas v
left join mapa_terminal m on m.n_serie = v.n_serie
left join cancelado c on c.stone_id = v.stone_id
where v.data_venda is not null
  -- Exclui apenas o que se sabe ser de outra unidade; o que nao resolve
  -- continua contando como Praia.
  and not exists (
    select 1
    from public.stone_estabelecimento e
    where e.stonecode = coalesce(v.stonecode, m.stonecode)
      and e.unidade <> 'PRAIA'
  );

comment on view public.recebimento_stone_net is
  'Vendas Stone da PRAIA no nivel da transacao, liquidas de cancelamento. Exclui Imprensa e PUB por stonecode e, no Pix (que nao traz stonecode), pelo numero de serie do terminal. Base unica do faturamento Stone: venda_diaria e recebimento_transacao_net leem daqui.';

-- ---------------------------------------------------------------------
-- Faturamento diario: Stone (Praia), especie, Fundopay e Pix QR do BB
-- ---------------------------------------------------------------------
create or replace view public.venda_diaria as
select
  dia,
  sum(bruto) as bruto,
  sum(qtd) as qtd_vendas
from (
  -- Stone da Praia. Le do recebimento_stone_net para o filtro de unidade
  -- e o liquido de cancelamento existirem num lugar so.
  select
    s.data_venda::date as dia,
    s.bruto_net as bruto,
    1 as qtd
  from public.recebimento_stone_net s

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

  union all

  -- Pix QR Code recebido no BB: liquida no proximo dia util, entao a venda
  -- e do dia anterior ao credito. Ver a 20260775000000 para a limitacao do
  -- credito de segunda-feira.
  select
    (b.data - 1) as dia,
    b.valor::numeric as bruto,
    1 as qtd
  from public.raw_bb b
  where b.lancamento = 'Pix-Recebido QR Code'
    and b.valor > 0
) x
group by dia;

comment on view public.venda_diaria is
  'Faturamento diario da PRAIA: Stone (liquido de cancelamento, so o estabelecimento da Praia), dinheiro em especie, Fundopay aprovada e Pix QR Code do BB (venda em D-1 do credito). Sempre pela data da venda e pelo valor bruto.';
