-- =====================================================================
-- Telas de recebimento passam a enxergar os quatro canais
-- =====================================================================
--
-- PROBLEMA
--   A 20260774000000 e a 20260775000000 colocaram Fundopay e Pix QR Code
--   do BB no `venda_diaria`, mas as views de recebimento nao foram
--   junto: elas leem `recebimento_stone_net` direto, entao continuaram
--   somando so Stone + especie.
--
--   O efeito e visivel dentro da propria `vendas.html`: o KPI
--   "Faturamento no mes" (que le `painel_recebimento_resumo`) mostrava
--   um numero e o grafico diario logo abaixo (que le `painel_diario`,
--   derivado do `venda_diaria`) mostrava outro. Em fev/2026:
--     KPI              118.077,57   (Stone 106.677,57 + especie 11.400,00)
--     grafico diario   134.084,59   (+ Fundopay 15.397,02 + Pix BB 610,00)
--
--   Faltavam R$ 186.169,62 espalhados por 13 meses -- exatamente o valor
--   que as duas migrations anteriores tinham somado ao faturamento. Os
--   meses mais afetados: ago/2025 (R$ 31.969,87), set/2025 (R$ 29.312,46)
--   e out/2025 (R$ 26.752,59).
--
-- SOLUCAO
--   + `recebimento_transacao_net`: nivel de transacao, unindo Stone e
--     Fundopay aprovada. E o novo bloco de montagem das tres views; a
--     `recebimento_stone_net` continua existindo e intacta.
--   ~ `painel_recebimento_resumo`, `painel_recebimento_canal` e
--     `painel_recebimento_hora` passam a ler a view unificada.
--
--   O Pix QR Code do BB entra em resumo e canal pela mesma regra ja
--   adotada no `venda_diaria` -- venda em D-1 do credito (ver
--   20260775000000) -- para que os meses fechem iguais nas duas telas.
--
-- FUSO HORARIO
--   `raw_stone_vendas.data_venda` e `timestamp` e
--   `raw_fundopay_vendas.data_venda` e `timestamptz`. A carga gravou a
--   hora local com a sessao em UTC, entao o instante armazenado le de
--   volta a hora de parede correta em UTC. O `at time zone 'UTC'` abaixo
--   torna isso explicito e imune a mudanca de timezone da sessao.
--   Conferido: a Fundopay concentra 16h-22h e zera de madrugada, curva
--   coerente com a da Stone -- nao ha deslocamento de 3 horas.
--
-- LIMITACAO ASSUMIDA
--   O Pix QR Code do BB fica **fora** do grafico por hora: o extrato so
--   traz a data do credito, nao o horario da venda. Sao R$ 5.222 em 11
--   meses (~R$ 475/mes), entao a curva horaria segue representativa. Por
--   isso `painel_recebimento_hora` le apenas a view de transacao.
--
-- OBJETOS
--   + public.recebimento_transacao_net (view nova)
--   ~ public.painel_recebimento_resumo (create or replace)
--   ~ public.painel_recebimento_canal  (create or replace)
--   ~ public.painel_recebimento_hora   (create or replace)
--
--   Nada e derrubado: os quatro dependentes (`app_painel_recebimento_*`
--   e `app_gerente_movimento_hora`) continuam validos porque as colunas
--   e os tipos das tres views nao mudam.
--
-- RISCO: baixo. Nenhuma tabela e tocada e a DRE nao usa estas views --
--   elas alimentam so as telas de faturamento.
-- =====================================================================

-- Nivel de transacao dos canais que tem lista de vendas.
-- A especie nao entra aqui (nao e transacao individual) e o Pix QR Code
-- do BB tambem nao (o extrato so tem o credito, nao a venda).
create or replace view public.recebimento_transacao_net as
select
  'stone'::text as fonte,
  s.id,
  s.data_venda,
  s.produto,
  s.bandeira,
  s.bruto_net
from public.recebimento_stone_net s

union all

select
  'fundopay'::text as fonte,
  f.id,
  (f.data_venda at time zone 'UTC') as data_venda,
  f.modalidade as produto,
  f.bandeira,
  f.valor_venda as bruto_net
from public.raw_fundopay_vendas f
where lower(btrim(f.situacao)) = 'aprovada';

comment on view public.recebimento_transacao_net is
  'Vendas no nivel da transacao, Stone e Fundopay aprovada, liquidas de cancelamento. Base das views painel_recebimento_*.';

-- ---------------------------------------------------------------------
-- Resumo mensal: alimenta os KPIs de vendas.html
-- ---------------------------------------------------------------------
create or replace view public.painel_recebimento_resumo as
with tx as (
  select
    to_char(t.data_venda, 'YYYY-MM') as ano_mes,
    date_trunc('month', t.data_venda)::date as mes,
    sum(t.bruto_net) as bruto,
    count(*) as qtd
  from public.recebimento_transacao_net t
  group by 1, 2
), pix_bb as (
  -- Venda em D-1 do credito, mesma regra do venda_diaria (20260775000000).
  select
    to_char(b.data - 1, 'YYYY-MM') as ano_mes,
    date_trunc('month', b.data - 1)::date as mes,
    sum(b.valor) as bruto,
    count(*) as qtd
  from public.raw_bb b
  where b.lancamento = 'Pix-Recebido QR Code'
    and b.valor > 0
  group by 1, 2
), esp as (
  select
    to_char(e.data, 'YYYY-MM') as ano_mes,
    date_trunc('month', e.data)::date as mes,
    sum(e.valor) as valor
  from public.venda_especie e
  group by 1, 2
), tudo as (
  select ano_mes, mes, bruto, qtd, 0::numeric as especie from tx
  union all
  select ano_mes, mes, bruto, qtd, 0::numeric from pix_bb
  union all
  select ano_mes, mes, 0::numeric, 0::bigint, valor from esp
)
select
  ano_mes,
  mes,
  round(sum(bruto) + sum(especie), 2) as recebido_total,
  sum(qtd)::bigint as qtd_transacoes,
  -- Ticket so dos canais transacionais: a especie nao tem contagem de
  -- pagamentos, entao entra no total e fica fora do denominador.
  round(sum(bruto) / nullif(sum(qtd), 0)::numeric, 2) as ticket_transacao
from tudo
group by ano_mes, mes
order by ano_mes;

-- ---------------------------------------------------------------------
-- Quebra por canal: alimenta o donut "De onde vem o faturamento"
-- ---------------------------------------------------------------------
-- Os rotulos ficam como cada fonte os escreve ("Credito" da Stone,
-- "Credito a vista" da Fundopay). O `normCanal` de vendas.html casa por
-- trecho e funde os dois na mesma fatia, entao o detalhe da origem nao
-- se perde e o grafico continua com uma fatia por canal.
create or replace view public.painel_recebimento_canal as
with fonte as (
  select
    to_char(t.data_venda, 'YYYY-MM') as ano_mes,
    coalesce(nullif(t.produto, ''), 'Cartão') as canal,
    t.bruto_net as valor,
    1::bigint as qtd
  from public.recebimento_transacao_net t

  union all

  select
    to_char(b.data - 1, 'YYYY-MM') as ano_mes,
    'Pix QRcode'::text as canal,
    b.valor,
    1::bigint as qtd
  from public.raw_bb b
  where b.lancamento = 'Pix-Recebido QR Code'
    and b.valor > 0
)
-- sum() de bigint devolve numeric; o cast preserva o tipo da coluna e
-- deixa o `create or replace` valido para os dependentes.
select ano_mes, canal, round(sum(valor), 2) as valor, sum(qtd)::bigint as qtd
from fonte
group by ano_mes, canal

union all

select
  to_char(e.data, 'YYYY-MM') as ano_mes,
  'Especie'::text as canal,
  round(sum(e.valor), 2) as valor,
  null::bigint as qtd
from public.venda_especie e
group by 1

order by 1, 3 desc;

-- ---------------------------------------------------------------------
-- Quebra por hora: alimenta o grafico horario e app_gerente_movimento_hora
-- ---------------------------------------------------------------------
-- Sem o Pix QR Code do BB, que nao tem horario (ver cabecalho).
create or replace view public.painel_recebimento_hora as
select
  to_char(t.data_venda, 'YYYY-MM') as ano_mes,
  extract(hour from t.data_venda)::integer as hora,
  round(sum(t.bruto_net), 2) as valor,
  count(*) as qtd
from public.recebimento_transacao_net t
group by 1, 2
order by 1, 2;
