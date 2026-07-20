-- =====================================================================
-- BS Cash fora do caixa: aprovisionamento de folha nao conta como saldo
-- =====================================================================
--
-- CONTEXTO (regra de negocio, definida pelo dono)
--   A conta BS Cash e usada como APROVISIONAMENTO de folha (13o, ferias,
--   rescisao). O dinheiro transferido para la e considerado "que nao existe
--   mais" para efeito de caixa: sai da Stone e nao volta a ser saldo
--   disponivel. A despesa de folha propriamente dita e reconhecida no DRE
--   quando o extrato do BS Cash e importado (origem='bs_cash').
--   Ou seja, caixa e DRE tem tempos diferentes de PROPOSITO:
--     - CAIXA: o dinheiro sai na transferencia Stone -> BS Cash.
--     - DRE:   a despesa de folha aparece no import do extrato do BS Cash.
--
-- PROBLEMA
--   Hoje o BS Cash fica "meio dentro, meio fora" do universo de caixa:
--     - O SALDO nunca entrou no saldo_anchor (que e Stone + BB; o
--       saldo_inicial so tem 'bb'). Isso esta correto para a regra acima.
--     - Mas as MOVIMENTACOES entram: as linhas origem='bs_cash' sao
--       empresa='PRAIA' e portanto passam pelo filtro do caixa_real_diario,
--       com as DUAS pernas (o credito da transferencia recebida e o debito
--       da folha paga aos funcionarios).
--   Como as duas pernas estao no fluxo, a transferencia se anula e o fluxo
--   passa a enxergar o BS Cash como parte do caixa — enquanto a ancora nao
--   enxerga. Resultado: o fluxo caminha num universo (Stone+BB+BS Cash) e a
--   ancora em outro (Stone+BB), e a reconstrucao historica fica inconsistente.
--
--   Isso fica PIOR quando o extrato do BS Cash e importado em dia: a perna
--   de entrada da transferencia aparece e cancela a saida da Stone no fluxo,
--   enquanto o saldo continua fora do anchor.
--
-- SOLUCAO
--   Tirar o BS Cash inteiro do universo de caixa: caixa_real_diario passa a
--   ignorar origem='bs_cash'. O fluxo passa a andar exatamente no mesmo
--   universo da ancora (Stone + BB):
--     - A transferencia Stone -> BS Cash conta como saida definitiva (apenas
--       a perna da Stone, que e a que de fato reduz o saldo bancario).
--     - O que acontece DENTRO do BS Cash (folha paga, tarifa da conta) nao
--       mexe mais no caixa.
--
-- O QUE NAO MUDA
--   - DRE e a pagina de Despesas: leem fato_financeiro direto, sem passar por
--     caixa_real_diario. A folha e a tarifa do BS Cash continuam aparecendo
--     normalmente por competencia, no import do extrato.
--   - saldo_anchor: segue Stone + BB + dinheiro em especie pendente (este
--     ultimo da 20260754000000). O BS Cash continua fora, como manda a regra.
--   - Projecao futura: fluxo_caixa_diario projeta os dias futuros por
--     recebimento_* / projecao_despesa_*, que nao usam caixa_real_diario.
--
-- RISCO: baixo, mas muda numeros historicos.
--   - A curva historica de caixa e os saldos de meses passados mudam, porque
--     as movimentacoes internas do BS Cash saem da conta. Essa e a correcao
--     pretendida: elas nunca deveriam contar sem o saldo correspondente.
--   - painel_saldo_atual.saldo_comp (comparativo de 1 mes) se ajusta junto.
--   - So reflete apos refresh do mv_fluxo_caixa_diario e recalculo do
--     snapshot — usar "Atualizar tudo agora" em status.html.
--
-- PENDENCIA CONHECIDA (nao tratada aqui, de proposito)
--   projecao_despesa_fixa ainda mede o "ja realizado" por competencia no DRE.
--   Como o caixa da folha sai na transferencia e a despesa so e reconhecida
--   no import do BS Cash, existe uma janela em que o colchao reprojeta folha
--   cujo dinheiro ja saiu. Sera tratado na recalibragem da projecao de
--   despesa fixa, medindo o "ja realizado" no universo de caixa (incluindo as
--   transferencias para o BS Cash).
--
-- OBJETOS
--   ~ public.caixa_real_diario  (passa a excluir origem='bs_cash')
-- =====================================================================

begin;

create or replace view public.caixa_real_diario as
select
  f.data_caixa as dia,
  sum(f.valor) as resultado_real
from public.fato_financeiro f
where f.empresa = any (array['PRAIA', 'BB'])
  -- BS Cash e aprovisionamento de folha: o dinheiro ja saiu do caixa na
  -- transferencia da Stone. O que acontece dentro dele nao volta a mexer no
  -- saldo. "is distinct from" preserva as linhas com origem nula.
  and f.origem is distinct from 'bs_cash'
group by f.data_caixa;

commit;
