-- =====================================================================
-- Pix QR Code recebido no BB entra no faturamento
-- =====================================================================
--
-- PROBLEMA
--   Vendas pagas por Pix QR Code caem direto na conta do BB e apareciam
--   so na camada de caixa/DRE, nunca no faturamento -- o mesmo buraco que
--   a Fundopay tinha antes da 20260774000000. Sao 131 creditos,
--   R$ 5.222,00, de jul/2025 a mai/2026 (~R$ 475 por mes).
--
--   Diferente da Stone e da Fundopay, aqui NAO existe lista de vendas:
--   o extrato so diz quando o dinheiro caiu. Era o motivo de ter ficado
--   de fora na migration anterior.
--
-- REGRA DE LIQUIDACAO (informada pelo usuario e confirmada nos dados)
--   O Pix QR Code liquida no proximo dia util. Os dados batem: nenhum dos
--   131 creditos caiu em sabado ou domingo, e a segunda-feira concentra 65
--   deles (R$ 2.465,00, quase metade do total) -- justamente porque o
--   credito de segunda carrega as vendas de sexta, sabado e domingo.
--
-- DECISAO (delegada pelo usuario: "pode decidir como achar melhor")
--   A venda e atribuida ao DIA ANTERIOR ao credito (D-1).
--
--   Por que D-1, e nao o dia do credito: um credito no dia 1o costuma se
--   referir a venda do ultimo dia do mes anterior. Usar a data do credito
--   jogaria essa venda para o mes errado, distorcendo justamente a
--   comparacao com a meta mensal. D-1 acerta o mes nesses casos.
--
--   Limitacao assumida e conhecida: no credito de segunda-feira, as vendas
--   de sexta e sabado tambem sao lancadas no domingo. O deslocamento e de
--   no maximo dois dias e nunca sai da mesma semana. Preferi isso a duas
--   alternativas piores:
--     - jogar tudo na sexta (dia util anterior estrito) subestimaria o fim
--       de semana, que e quando o restaurante mais vende;
--     - ratear entre sexta/sabado/domingo pelo movimento da Stone daria
--       uma precisao que R$ 475 por mes nao justifica, e exigiria calendario
--       de feriados dentro de uma view ja sensivel a desempenho.
--   Como o rateio erra no maximo dois dias dentro da semana, o total
--   mensal fica correto exceto quando uma virada de mes cai no meio do fim
--   de semana -- efeito de poucos reais.
--
-- SOLUCAO
--   ~ venda_diaria ganha um quarto braco lendo raw_bb, tipo
--     'Pix-Recebido QR Code', com dia = data do credito menos um dia.
--     Conta 1 em qtd, como os demais canais de cartao/Pix.
--
--   Sem dupla contagem: venda_diaria e FATURAMENTO (o que foi vendido) e
--   fato_financeiro e CAIXA (o dinheiro que entrou). O mesmo Pix aparece
--   nos dois, em camadas distintas -- exatamente como ja acontece com a
--   Stone e com a Fundopay.
--
-- OBJETOS
--   ~ public.venda_diaria (create or replace view; mesmas colunas)
--
-- RISCO: baixo. Faturamento sobe R$ 5.222,00 distribuidos em 11 meses
--   (0,2% do periodo). A DRE nao muda. Nenhum lancamento e alterado.
-- =====================================================================

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

  union all

  -- Pix QR Code recebido no BB: liquida no proximo dia util, entao a venda
  -- e do dia anterior ao credito. Ver o cabecalho desta migration para a
  -- limitacao do credito de segunda-feira.
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
  'Faturamento diario: Stone (liquido de cancelamento), dinheiro em especie, Fundopay aprovada e Pix QR Code do BB (venda em D-1 do credito). Sempre pela data da venda e pelo valor bruto.';
