# Supabase Schema - Projeto Sir Fisher App

## Visão geral
Este documento resume o schema público do Supabase usado pelo painel Sir Fisher
App. O conteúdo acompanha os contratos do front-end e as migrations versionadas
no repositório.

## Tabelas e views principais

### analise_individual
- Tipo: view ou tabela de consulta
- Uso: alimenta `analise_individual.html`
- Propósito: lista transações que precisam ser classificadas individualmente, com informações de origem, valor e contraparte.
- Colunas importantes:
  - `origem`
  - `raw_id`
  - `empresa`
  - `unidade`
  - `data_caixa`
  - `movimentacao`
  - `natureza`
  - `valor`
  - `contraparte_nome`
  - `contraparte_doc`
  - `fornecedor`

### categoria_dre
- Tipo: tabela de categorias DRE
- Uso: alimenta `analise_individual.html` e `classificar_excecoes.html`
- Propósito: define categorias e grupos DRE para classificação das transações.
- Colunas importantes:
  - `categoria`
  - `dre_grupo`
  - `natureza`

### ajuste_manual
- Tipo: provável tabela de ajustes manuais
- Uso: não há acesso direto via painel HTML, mas a página `analise_individual.html` faz `upsert` nesta tabela.
- Propósito: registra classificações manuais que foram aplicadas a transações emergenciais.
- Colunas importantes:
  - `id`
  - `origem`
  - `raw_id`
  - `categoria`
  - `observacao`
  - `criado_em`

### painel_saldo_atual
- Tipo: painel / view agregada
- Uso: `caixa.html`, `index.html`
- Propósito: fornece saldo atual e saldo comparativo para o painel financeiro.
- O wrapper `app_painel_saldo_atual` preserva o saldo atual da fonte original,
  mas busca `saldo_comp` no snapshot diário da data comparada. Isso impede que
  dinheiro pendente no corte atual seja reaplicado ao passado.
- Colunas importantes:
  - `data_ref`
  - `saldo_atual`
  - `data_comp`
  - `saldo_comp`

### painel_saldo_fim_mes
- Tipo: painel / view agregada
- Uso: `caixa.html`, `index.html`
- Propósito: dados de saldo no final do mês para histórico e projeção.
- No wrapper `app_painel_saldo_fim_mes`, meses já encerrados usam o último
  snapshot diário disponível no próprio mês. O mês corrente e os meses futuros
  continuam usando a projeção original.
- Colunas importantes:
  - `mes`
  - `ano_mes`
  - `saldo_fim`
  - `situacao`

### painel_fluxo_caixa
- Tipo: painel / view agregada
- Uso: `caixa.html`
- Propósito: mostra fluxo de caixa diário, saldo real/projetado e entradas/saídas.
- As linhas realizadas usam `mv_saldo_caixa_diario_detalhado`; as linhas
  projetadas preservam a memória prospectiva anterior. No corte, as duas
  fontes convergem e mantêm a continuidade da curva.
- Colunas importantes:
  - `dia`
  - `tipo`
  - `saldo`
  - `saldo_real`
  - `saldo_projetado`
  - `entrada_projetada`
  - `saida_projetada`
  - `resultado_dia`

### recebimento_conhecido
- Tipo: painel / view agregada
- Uso: `caixa.html`
- Propósito: mostra recebimentos conhecidos por dia.
- Colunas importantes:
  - `dia`
  - `valor`

### recebimento_projetado
- Tipo: painel / view agregada
- Uso: `caixa.html`
- Propósito: mostra projeções de recebimentos por dia.
- Colunas importantes:
  - `dia`
  - `valor`

### projecao_despesa_fixa
- Tipo: painel / view agregada
- Uso: `caixa.html`, `dre.html`
- Propósito: mostra projeção de despesas fixas por dia. Calcula a média mensal dos 3 meses fechados anteriores (débitos dos grupos DRE PESSOAL, INFRAESTRUTURA, MARKETING E PUBLICIDADE e IMPOSTOS em `fato_financeiro`), subtrai o realizado na mesma fonte e nos mesmos grupos e distribui o restante (nunca negativo) pelos dias do mês após o corte de caixa. Contas recorrentes ativas, do tipo despesa, marcadas para entrar nos totais, com média positiva e ainda sem pagamento na competência entram no vencimento como previsão explícita; seu valor reduz antes o colchão genérico para evitar dupla contagem. Meses futuros sem realizado projetam a média cheia. Redefinida em `20260760000000_previsao_contas_abertas_no_caixa.sql`.
- Colunas importantes:
  - `dia`
  - `valor`

### projecao_despesa_direta
- Tipo: painel / view agregada
- Uso: `caixa.html`, `dre.html`
- Propósito: mostra projeção de despesas diretas por dia.
- Colunas importantes:
  - `dia`
  - `valor`

### painel_ultima_carga
- Tipo: painel / view simples
- Uso: `caixa.html`, `dre.html`, `index.html`, `vendas.html`
- Propósito: indica a data/hora da última carga de dados.
- Colunas importantes:
  - `ultima`

### painel_cargas
- Tipo: painel / view simples
- Uso: `caixa.html`, `dre.html`, `index.html`, `vendas.html`
- Propósito: mostra histórico de cargas e fontes.
- Colunas importantes:
  - `quando`
  - `fontes`

### painel_saldo_por_conta
- Tipo: painel / view agregada
- Uso: `caixa.html`
- Propósito: exibe saldo por conta bancária ou fonte de saldo.
- Colunas importantes:
  - `conta`
  - `saldo`
  - `data_ref`

### excecoes
- Tipo: view / tabela de exceções
- Uso: `classificar_excecoes.html`
- Propósito: lista fornecedores não categorizados para classificação manual.
- Colunas importantes:
  - `contraparte_nome`
  - `contraparte_doc`
  - `chave_tipo`
  - `chave_valor`
  - `qtd_lancamentos`
  - `total`
  - `natureza`
  - `data_min`
  - `data_max`

### de_para
- Tipo: tabela de mapeamento
- Uso: `classificar_excecoes.html` para inserir novas regras de classificação
- Propósito: armazena categorias automáticas/manuais para fornecedores.
- Colunas importantes:
  - `id`
  - `chave_tipo`
  - `chave_valor`
  - `fornecedor`
  - `categoria`
  - `ativo`
  - `atualizado_em`
- `chave_valor` guarda o nome **original** normalizado e é o que casa com o
  lançamento; `fornecedor` é só o **rótulo exibido**. Nenhum join, filtro,
  agrupamento ou soma depende de `fornecedor` — ele aparece como coluna de saída
  em `fato_financeiro` e em `app_classificacoes_recentes`, e a DRE agrupa por
  `categoria`. Ou seja, renomear um apelido nunca move valor.
- **Convenção do apelido** (firmada em `20260776000000`): inicial maiúscula,
  conectivo em minúscula ("Vai com Peixe"), acento preservado — a mesma forma que
  `tituloCase` em `classificar_excecoes.html` sugere por padrão. Manter essa
  convenção ao criar regra nova: chaves diferentes do mesmo fornecedor continuam
  surgindo e, com grafias divergentes, o relatório volta a quebrar em várias
  linhas. Contas do próprio grupo seguem o padrão `Sir Fisher - <conta>`.

### mv_despesa_diaria / listar_ranking_fornecedor
- Tipo: materialized view + função `SECURITY DEFINER`
- Uso: ranking de fornecedores e "vazamentos" em `despesas.html`
- `mv_despesa_diaria` tem a mesma regra da `mv_despesa_mensal`, só que por
  **dia** (13.425 linhas, 1,1 MB). Entra no `refresh_painel()` junto com as
  demais. Não é exposta na Data API — o acesso é pela RPC.
- **Por que a MV existe:** filtrar `fato_financeiro` por `data_competencia`
  custa ~1,5 s, porque essa coluna é **calculada** por ramo da view e não usa
  índice — obriga a montar a união das cinco raws mais o `de_para`. Marcar a CTE
  como `MATERIALIZED` **não** resolve (o custo é montar a view, não expandi-la
  várias vezes). Com a MV, a RPC responde em 183 ms.
- `listar_ranking_fornecedor(p_ano_mes, p_meses_base default 6)` devolve os
  fornecedores do mês com o realizado até o dia de corte e a média dos meses
  anteriores **até o mesmo dia do mês** — sem tendência. Em mês fechado o corte
  vai a 31 e cobre o mês inteiro.
- **Por que o mesmo período, e não tendência:** a tendência é um multiplicador da
  curva de **vendas**, e despesa fixa não segue venda — é paga uma vez e não
  cresce com o avanço do mês. Cortando os dois lados no mesmo dia, o próprio dado
  separa fixo de variável: para Imposto, Enel e iFood Benefícios a média até o
  dia 26 é **idêntica** à do mês cheio (nada é pago depois), enquanto para B&C,
  Ambev e SOLMAR ela fica em 82–90% (a compra continua).
- As categorias `Folha Salarial` e `Diária` vêm **colapsadas** em uma linha cada,
  com a contagem em `pessoas`. São ~58 pessoas físicas que disputavam as 15
  posições com fornecedor negociável; o salário individual não é a informação
  útil e não deve ficar exposto no painel. As demais categorias de PESSOAL
  seguem individuais de propósito — iFood Benefícios, Plano Dentário, Fardamento
  e Endomarketing são fornecedores de verdade.
- A RPC serve **quatro** blocos de `despesas.html`: ranking, vazamentos, KPI de
  concentração e "Recorrente vs pontual". Todos na mesma base, para não
  discordarem entre si.
- Três contadores, cada um com um propósito — não confundir:
  - `meses_base` — meses anteriores com gasto **até o corte**. É o divisor da
    média, então aqui o corte tem que valer.
  - `meses_presente` — meses anteriores com gasto no **mês cheio**, sem corte. É
    o dado da recorrência, que pergunta "aparece todo mês?" (estrutural). Com o
    corte, quem sempre cobra no fim do mês seria classificado como pontual.
  - `meses_janela` — quantos meses da janela têm algum gasto; denominador do
    limiar de presença, que se adapta quando o histórico é curto.
- Colapsar a folha mudou dois números de forma relevante, e para melhor:
  concentração top 5 de 35,2% para **67,5%** (a folha entrava picotada em 33
  pessoas e nunca chegava ao top 5) e recorrente de 86,9% para **97%** (19
  pessoas com menos de 4 meses de casa carregavam R$ 15,2 mil classificados como
  gasto pontual).
- Limitação assumida: boleto que muda de dia entre meses gera variação falsa
  enquanto o mês não fecha; corrige-se sozinho no fechamento.
- Criados em `20260778000000_ranking_fornecedor_mesmo_periodo.sql`; colunas de
  recorrência em `20260779000000_ranking_alinha_concentracao_e_recorrencia.sql`.

### app_classificacoes_recentes e RPCs de classificação
- Tipo: view protegida e funções `SECURITY DEFINER`
- Uso: `analise_individual.html` e `classificar_excecoes.html`
- Propósito: listar o estado atual das classificações, corrigir categorias e
  desfazer regras ou ajustes sem criar uma tabela de histórico.
- A view combina registros ativos de `de_para` e `ajuste_manual`.
- RPCs disponíveis:
  - `classificar_excecao(text, text, text, text)`;
  - `classificar_transacao(text, bigint, text)`;
  - `corrigir_classificacao(text, bigint, text)`;
  - `desfazer_classificacao(text, bigint)`.
- Todas validam o papel autenticado; correção e desfazer atuam sobre o estado
  atual e não preservam versões anteriores.

### painel_dre_cascata
- Tipo: painel / view agregada
- Uso: `dre.html`
- Propósito: fornece a cascata DRE mensal realizada com receita, CMV, despesas e resultado líquido. No mês aberto, `dre.html` calcula os KPIs projetados somando ao resultado operacional realizado a receita futura da curva de vendas e descontando as despesas diretas e fixas futuras das mesmas views usadas pelo caixa; itens abaixo da operação permanecem pelo realizado.
- Colunas importantes:
  - `mes`
  - `ano_mes`
  - `receita`
  - `cmv`
  - `impostos`
  - `margem_contribuicao`
  - `mc_perc`
  - `pessoal`
  - `infraestrutura`
  - `marketing`
  - `resultado_operacional`
  - `margem_op_perc`
  - `nao_operacional`
  - `contabil`
  - `capex`
  - `nao_categorizado`
  - `resultado_liquido`
  - `margem_liq_perc`
  - `cmv_perc`
  - `pessoal_perc`

### painel_resumo_mensal
- Tipo: painel / view agregada
- Uso: `index.html`, `vendas.html`
- Propósito: resumo mensal de faturamento, receita, despesa e margem.
- Colunas importantes:
  - `mes`
  - `ano_mes`
  - `ano`
  - `faturamento`
  - `faturamento_proj`
  - `qtd_vendas`
  - `ticket_medio`
  - `meta`
  - `perc_meta`
  - `receita`
  - `despesa`
  - `resultado`
  - `cmv`
  - `pessoal`
  - `cmv_perc`
  - `pessoal_perc`
  - `margem_perc`
  - `saldo_fim`
  - `saldo_situacao`

### painel_composicao_despesa
- Tipo: painel / view agregada
- Uso: `index.html`
- Propósito: composição de despesas por grupo.
- Colunas importantes:
  - `mes`
  - `ano_mes`
  - `grupo`
  - `valor`

### painel_margem_contribuicao
- Tipo: painel / view agregada
- Uso: `index.html`
- Propósito: percentual de margem de contribuição mensal.
- Colunas importantes:
  - `mes`
  - `ano_mes`
  - `mc_perc`

### painel_diario
- Tipo: painel / view agregada
- Uso: `index.html`, `vendas.html`
- Propósito: vendas diárias, metas e projeções.
- Colunas importantes:
  - `dia`
  - `mes`
  - `venda_dia`
  - `meta_dia`
  - `meta_mes`
  - `peso_total`
  - `projecao_fechamento`

### projecao_venda_diaria
- Tipo: view; venda realizada até `corte_venda` e projetada depois, rateada
  pelo `peso_ajustado` do dia.
- Uso: `vendas.html`, `caixa.html`, `dre.html`, `listar_calendario_financeiro`,
  e como base de `recebimento_projetado` e `projecao_despesa_direta`.
- Regra por mês: mês anterior ao do corte usa o realizado; o mês do corte usa
  a tendência (ou a meta, se não houver tendência); meses futuros usam a meta.
- **Desempenho (20260771000000).** A CTE `mes_total` executava subqueries
  correlacionadas para cada um dos 68 meses de `calendario` (soma de
  `venda_diaria`, `meta_mensal` e `peso_mensal` do mês, além de reavaliar
  `tendencia_mes`), custando 1,21 s enquanto todas as dependências somavam
  0,35 s. Passou a usar uma agregação única mais `left join`, caindo para
  0,34 s com as 2.064 linhas idênticas. Como duas views derivam desta, o ganho
  se propaga. Nota de equivalência: `tendencia_mes` pode não ter linha, então
  o join é `left join lateral ... on true` — um `cross join` apagaria as linhas.

### raw_fundopay_vendas / venda_diaria
- `venda_diaria` é a base do faturamento (planejamento, vendas.html, metas,
  tendência, peso do dia e, por `projecao_venda_diaria`, a projeção de caixa).
- Reúne **quatro canais**, sempre pela **data da venda** e pelo **valor bruto**:
  `raw_stone_vendas` (líquido de cancelamento), `venda_especie` (sangrias
  registradas à mão), `raw_fundopay_vendas` (maquininha paralela usada de
  mai/2025 a mai/2026) e o Pix QR Code recebido no BB.
- O Pix QR Code (`raw_bb`, lançamento `Pix-Recebido QR Code`) é o único canal
  sem lista de vendas: o extrato só informa quando o dinheiro caiu. Ele liquida
  no próximo dia útil — confirmado nos dados, já que nenhum dos 131 créditos caiu
  em sábado ou domingo e a segunda concentra 65 deles —, então a venda é lançada
  em **D-1 do crédito**. D-1 e não a data do crédito porque um crédito no dia 1º
  costuma ser venda do último dia do mês anterior, e usar a data do crédito
  erraria o mês na comparação com a meta. Limitação assumida: no crédito de
  segunda, vendas de sexta e sábado também caem no domingo (no máximo dois dias,
  sempre na mesma semana). Ver `20260775000000_pix_qrcode_bb_no_faturamento.sql`.
- O depósito de dinheiro que aparece no extrato do BB (`Dep dinheiro ATM`,
  R$ 136 mil) **não** entra e não deve entrar: é o mesmo dinheiro já contado por
  `venda_especie` na data da venda. Contar os dois duplicaria.
- Em `raw_fundopay_vendas` a coluna `situacao` traz Aprovada, Negada e Desfeita;
  a view filtra `lower(btrim(situacao)) = 'aprovada'`. Negada é cartão recusado
  (não houve venda). O número do cartão não é gravado.
- Carga: `scripts/importacao/07_importar_fundopay.py`, dedup pelo `ID Venda`.
- Criados em `20260774000000_vendas_fundopay_no_faturamento.sql`.

### corte_venda / corte_caixa
- Tipo: views de corte (1 linha, coluna `dia`).
- Uso: base de todas as views de tendência/projeção (`tendencia_mes`,
  `projecao_venda_diaria`, `painel_diario`, `painel_tendencia_diaria`,
  fluxo de caixa e `listar_calendario_financeiro`).
- Propósito: definir o último **dia completo** de dados. Dias após o corte são
  tratados como "projetado"; dias até o corte como "real".
- Regra (desde `20260745000000_corte_considera_dia_completo.sql`):
  - `corte_venda` = `least(max(data_venda) da raw_stone_vendas, max(data) da
    venda_especie, ontem em America/Sao_Paulo)`. Um dia só conta quando as duas
    fontes já passaram por ele e o dia terminou. Semântica da espécie: dia sem
    lançamento mas com lançamento posterior = zero implícito (conta); dia sem
    lançamento na fronteira = fica fora até o próximo lançamento; lançar R$ 0
    explícito avança a fronteira.
  - `corte_caixa` = `least(max(data_caixa) de fato_financeiro, ontem em
    America/Sao_Paulo)`.
- `tendencia_mes` usa `corte_venda.dia` diretamente como `dia_ref` (não mais
  `max(dia)` do mês, que deixava espécie adiantada furar o corte).

### mv_saldo_caixa_diario_detalhado / detalhar_saldo_caixa_dia(date)
- Tipo: materialized view interna e RPC diária `SECURITY DEFINER`, protegida
  pela permissão de `calendario.html`.
- Uso: saldo realizado e popover da coluna Saldo caixa em `calendario.html`.
- Propósito: preservar a memória de fechamento de cada data separada em saldo
  Stone, saldo Banco do Brasil, saldo Inter e dinheiro em espécie ainda não
  depositado naquela data. O total diário é a soma dos componentes; BS Cash
  continua fora do caixa disponível. O saldo Inter é a soma acumulada de
  `raw_inter` (a conta nasceu zerada em mai/2025 e foi encerrada zerada em
  jun/2026), então só afeta as datas em que a conta tinha dinheiro.
- O dinheiro pendente é reconstituído pelos eventos de custódia: entra na data
  da venda em espécie e sai na data local em que a sangria é marcada como
  depositada. Assim, o pendente atual não é reaplicado retroativamente aos
  fechamentos antigos.
- A variação positiva do dinheiro pendente participa das entradas realizadas;
  a variação negativa participa das saídas. No depósito, a baixa física e o
  crédito bancário ficam visíveis separadamente, preservando a igualdade
  `saldo do dia - saldo anterior = recebimentos - despesas`.
- A view não possui `grant` direto ao navegador. A RPC retorna somente uma
  linha e é carregada sob demanda, com cache no front-end.
- Importações a atualizam pelo `refresh_painel()`. Alterações de sangria criam
  apenas um job `pg_cron` temporário para este snapshot pequeno; o worker se
  remove depois do refresh. Não existe agendamento permanente nem diário.
- Criados em `20260763000000_saldo_diario_detalhado.sql`; coluna `saldo_inter`
  adicionada em `20260765000000_conta_inter_e_extrato_bb_2025.sql`.

### raw_inter / conta Inter
- Tipo: tabela raw de extrato (carga única) da conta Inter, encerrada em
  jun/2026, usada pela unidade PRAIA para receber vendas Fundopay e pagar
  despesas entre mai/2025 e jun/2026.
- Carga: `scripts/importacao/06_importar_inter.py` (dedup por hash; tolera
  codificação mista UTF-8/latin-1 no CSV exportado do Inter).
- Corte no `fato_financeiro`: o histórico legado (`raw_historico`, empresa
  `Inter`, até 17/07/2025, já classificado manualmente) permanece; `raw_inter`
  entra apenas com `data` posterior ao fim desse histórico. Vendas Fundopay
  ("Vendas Crédito"/"Vendas Débito") classificam como Recebível de Cartão;
  transferências, como Transferencia entre Contas; débitos seguem o `de_para`.
- O mesmo padrão de corte foi aplicado ao braço `bb`: `raw_bb` só entra após o
  fim do histórico BB (16/07/2025), permitindo importar os extratos BB de
  jul-dez/2025 sem duplicar a quinzena já coberta.
- O `de_para` ganhou chaves de nome das contas do próprio grupo (Sir Fisher,
  Sirfisher, Sir Fisher Pub, Sir Fisher Imprensa, BS, Hemile/Inter), todas
  mapeando para Transferencia entre Contas, e 12 créditos históricos
  (R$ 44.000, set-nov/2025) confirmados par a par como transferências internas
  foram reclassificados de PIX/RECEITAS para Transferencia entre Contas.
- Reconciliação conferida após a carga: `raw_inter` (extrato completo) bate com
  `fato_financeiro` origem `inter` mais o histórico legado, com diferença de
  R$ 0,72 — deslocamento de um dia entre a data do extrato e a data registrada
  no histórico em alguns pares de dias, mais centavos de arredondamento em dois
  lançamentos de 2025. O saldo Inter zera em 20/06/2026 e permanece zerado.
- Criados em `20260765000000_conta_inter_e_extrato_bb_2025.sql`, com dois
  complementos:
  - `20260766000000_indice_corte_historico_por_empresa.sql`: índice
    `raw_historico (empresa, data_hora desc)`. Sem ele, os dois cortes por
    empresa viravam seq scan em 47 mil linhas e, como `fato_financeiro` não é
    materializada e o `saldo_mensal_calculado` a expande dezenas de vezes, o
    recálculo consumiu memória a ponto de reiniciar a instância e formar um
    crashloop com o job `sirfisher-processar-recalculo-saldo`. Com o índice, o
    custo do `saldo_mensal_calculado` caiu de 96.220 para 56.248 e o recálculo
    completo roda em ~20s. **Qualquer novo corte por subselect em tabela grande
    dentro do `fato_financeiro` precisa de índice equivalente.**
  - `20260767000000_corrige_de_para_contas_do_grupo.sql`: três chaves do grupo
    já existiam como Recebível de Cartão e o insert `where not exists` da
    20260765000000 as ignorou; Pix enviados para contas da própria empresa
    entravam na DRE como despesa do grupo RECEITAS (14 débitos, R$ 43.926,95).
  - `20260776000000_consolida_apelidos_de_fornecedor.sql`: 85 rótulos ajustados
    (31 rótulos distintos → 17 nos fornecedores tocados). Preencheu as três
    chaves do grupo que a 20260767000000 deixou com `fornecedor` NULL — apareciam
    em branco no relatório e somavam R$ 461.841,85 — e uniu o que era o mesmo
    fornecedor sob nomes diferentes, com destaque para `CRBSSACDDFORTALEZA`
    (centro de distribuição da Ambev, 309 lançamentos, R$ 457.402,19), que
    figurava separado da própria Ambev. Só rótulo: DRE conferida idêntica linha a
    linha nas 62 linhas de (grupo, categoria).
- A conta Inter era da empresa, mas registrada no CNPJ da titular. A separação
  correta é pelo documento da contraparte, e o `de_para` já a reproduz sem
  ajuste adicional: os lançamentos da conta chegam com o nome prefixado pelo
  CNPJ (`35220527 HEMILE ALEXANDRE SILVA`, documento no formato
  `##.###.###/####-##`) e a chave `35220527HEMILEALEXANDRESILVA` os mapeia para
  Transferencia entre Contas; os pagamentos à pessoa física chegam sem prefixo
  e com CPF mascarado (`***.###.###-**`), e a chave `HEMILEALEXANDRESILVA`
  mantém Folha Salarial. Conferido: os dois grupos não se misturam — 9
  lançamentos no CNPJ (R$ 28.000 de crédito e o aporte inicial de R$ 100) e os
  demais no CPF. Confirmação independente: o extrato da Inter só tem três tipos
  de entrada (Vendas Crédito e Débito da Fundopay, mais os R$ 100 iniciais),
  ou seja, a conta nunca recebeu transferência das outras contas do grupo,
  então os débitos para o CPF não podem ter ido para ela.

### Classificação automática por tipo de lançamento (fontes vivas)
- O `fato_financeiro` classifica em duas etapas: primeiro o `de_para` pelo nome
  da contraparte, depois regras por **tipo de lançamento** específicas de cada
  origem. O `de_para` sempre tem precedência.
- As regras por tipo existem porque, em algumas fontes, o nome da contraparte é
  o cliente que pagou — e não um fornecedor recorrente. Sem elas, cada cliente
  novo vira uma exceção nova e a fila de `classificar_excecoes.html` cresce a
  cada importação sem que haja decisão real a tomar.
- Cobertura por origem: `stone_extrato` (créditos → Recebível de Cartão, PIX,
  TED ou Transação), `bs_cash` (créditos e folha/tarifa/estorno), `inter`
  (vendas Fundopay → Recebível de Cartão; transferências) e `bb`, incluída em
  `20260768000000_classifica_lancamentos_bb_por_tipo.sql`:
  - `Pix-Recebido QR Code` → PIX (venda por QR Code; usa o mesmo rótulo dos
    lançamentos que o `de_para` já classificava assim no próprio BB)
  - `Tarifa Pix Recebido`, `Tarifa Pacote de Serviços`, `Cobrança de I.O.F.` e
    `Cobrança de Juros` → Tarifas Bancárias
  - `Pix-Envio devolvido` e `Pix-Recebimento devolvido` → pagamento devolvido
- Ficam fora de propósito os tipos cuja categoria não é determinada pelo tipo:
  `Pix - Enviado`, `Pagamento de Boleto` (já virou Aluguel, Gás e Plano
  Dentário em casos distintos) e `Pagamento de Impostos`.

### Histórico de caixa unificado nas telas
- Desde `20260764000000_caixa_historico_usa_saldo_diario.sql`, a curva
  realizada de `caixa.html`, os fechamentos de meses encerrados e o saldo de
  comparação da Visão Geral usam a mesma memória diária do Calendário.
- A variação percentual de saldo exibida ao gerente usa os mesmos fechamentos.
- A correção é transparente ao front-end: os contratos `app_*` não mudaram.
- Dias ou meses sem snapshot usam o valor da fonte anterior como fallback.
- Saldo atual, projeções futuras, faturamento e DRE não são alterados.

### listar_calendario_financeiro(date)
- Tipo: RPC mensal `SECURITY DEFINER`, protegida pela permissão de `calendario.html`.
- Uso: `calendario.html`.
- Propósito: consolidar, por dia, meta e faturamento acumulados, vendas por
  forma, recebimentos, despesas recorrentes/não recorrentes e saldo de caixa.
- O saldo realizado vem de `mv_saldo_caixa_diario_detalhado`, com os
  componentes efetivamente mantidos em cada data. Depois do corte das cargas,
  a RPC preserva o último saldo realizado e calcula cada saldo futuro
  pela mesma memória exibida na linha: `saldo anterior + recebimentos -
  despesas`. Assim, a projeção não depende do snapshot de `caixa.html` estar
  atualizado para conciliar com as colunas diárias.
- No realizado, recebimentos e despesas usam o mesmo universo do saldo:
  `fato_financeiro` de PRAIA/BB, sem a origem BS Cash. Créditos Stone do tipo
  `Transação` representam vendas via QR Code; tipo `Pix`, TED e demais créditos
  são outras entradas/transferências. A variação do dinheiro físico também é
  incorporada para reconciliar as colunas com o saldo detalhado. Todos os
  débitos desse universo aparecem em Despesas, mesmo quando não entram na DRE.
  A parcela recorrente usa
  pagamentos de `conta_recorrente_pagamento` limitada ao total financeiro do
  dia; o restante é apresentado como não recorrente.
- **Desempenho (20260770000000).** A RPC chegou a levar 7,5–8,8 s contra o
  limite de 8 s do PostgREST, o que fazia `calendario.html` falhar de forma
  intermitente. O `explain analyze` mostrou 355 InitPlans e a CTE `de_para_u`
  repetida 24 vezes — ou seja, `fato_financeiro` expandida 24 vezes na mesma
  consulta. Isoladas, as fontes somam 1,65 s; juntas, passavam de 8 s. Duas
  mudanças resolveram, sem alterar nenhum valor: `entradas_reais` e
  `saidas_reais` (dois scans do mesmo recorte, diferindo só na movimentação)
  passaram a sair de uma CTE única `movimento_real`; e as CTEs de fonte viraram
  `AS MATERIALIZED`, de modo que cada uma é avaliada uma só vez em vez de ser
  reexpandida pelo planner. Medido depois: jul/2026 2,3 s e os demais meses
  ~1,2 s. **Ao acrescentar fonte nova aqui, declare-a como CTE materializada** —
  sem isso o inline volta a multiplicar as avaliações de `fato_financeiro`.

### listar_despesas_dia(date)
- Tipo: RPC diária `SECURITY DEFINER`, protegida pela permissão de `calendario.html`.
- Uso: popover de despesas de `calendario.html`, carregada sob demanda (com cache por dia).
- Propósito: listar as despesas individuais de um dia realizado (descrição, categoria, valor).
- Mesmo recorte da CTE `saidas_reais` de `listar_calendario_financeiro`
  (`fato_financeiro` por `data_caixa`, Débito, empresas PRAIA/BB e origem
  diferente de BS Cash), acrescido da baixa do dinheiro pendente quando uma
  sangria é depositada, para a soma da lista bater com a coluna Despesas.
- Criada em `20260737000000_listar_despesas_dia.sql`; o recorte foi alinhado
  ao fluxo integral do caixa em
  `20260762000000_calendario_realizado_concilia_caixa.sql`.

### venda_especie
- Tipo: tabela de vendas por espécie
- Uso: `venda_especie.html`
- Propósito: registra vendas por tipo de transação ou espécie.
- Colunas importantes:
  - `id`
  - `data`
  - `unidade`
  - `valor`
  - `observacao`
  - `criado_em`
  - `recolhida_em`
  - `depositada_em`
  - `cadastrado_por`
  - `recolhida_por`
  - `depositada_por`
- Os dois timestamps controlam a custódia física da sangria e não geram
  lançamento financeiro. A RPC `alterar_status_sangria(bigint, text)` garante
  que o depósito só possa ser marcado depois do recolhimento.
- A view protegida `app_venda_especie_controle` expõe os nomes dos responsáveis
  sem publicar os IDs ou dados do usuário. Novos valores são gravados pela RPC
  `salvar_sangria(date, text, numeric)` para vincular o usuário autenticado.
- Na implantação do controle de responsáveis, os registros preexistentes foram
  marcados como recolhidos e depositados, sem atribuição retroativa de usuário.
- Salvar um valor ou alterar o status solicita a atualização assíncrona apenas
  de `mv_saldo_caixa_diario_detalhado`, por job temporário e auto-removível. A
  ação não executa o refresh pesado do painel e não mantém cron permanente.

### conta_recorrente / conta_recorrente_pagamento
- Tipo: cadastro operacional e histórico mensal de contas recorrentes.
- Uso: `contas_recorrentes.html`.
- O cadastro guarda nome, dia de vencimento, categoria, unidade, tipo e estado
  ativo/inativo. A opção `incluir_totais` preserva o total operacional sem
  cartão BTG e pró-labore/lucro. O pagamento guarda a competência separada da
  data efetiva em que a conta foi paga.
- `sem_movimento` substitui os antigos marcadores simbólicos de R$ 0,01 sem
  contaminar médias ou totais financeiros.
- A RPC `listar_contas_recorrentes(date)` calcula a média dos três últimos
  pagamentos reais anteriores à competência escolhida.
- Escritas usam as RPCs `salvar_conta_recorrente`,
  `salvar_pagamento_recorrente` e `excluir_pagamento_recorrente`.
- O histórico da planilha antiga pode ser enviado uma única vez pela RPC admin
  `importar_contas_recorrentes_legado(jsonb, jsonb)`. A importação é idempotente
  e não sobrescreve pagamentos posteriormente corrigidos de forma manual.
- As views protegidas `app_contas_recorrentes_pagamentos` e
  `app_contas_recorrentes_totais` alimentam histórico e gráfico mensal.

### recebimento_transacao_net
- Tipo: view (nível de transação)
- Uso: base das três `painel_recebimento_*`
- Propósito: unir as vendas que **têm lista de transações** — `raw_stone_vendas`
  (líquida de cancelamento, via `recebimento_stone_net`) e `raw_fundopay_vendas`
  com `situacao = 'aprovada'`. A espécie não entra (não é transação individual) e
  o Pix QR Code do BB também não (o extrato só tem o crédito, não a venda).
- Colunas: `fonte`, `id`, `data_venda`, `produto`, `bandeira`, `bruto_net`.
- `raw_stone_vendas.data_venda` é `timestamp` e `raw_fundopay_vendas.data_venda`
  é `timestamptz`. A carga gravou hora local com a sessão em UTC, então a leitura
  em UTC devolve a hora de parede correta; a view aplica `at time zone 'UTC'`
  para deixar isso explícito e imune a mudança de timezone da sessão.
- Criada em `20260777000000_recebimento_inclui_fundopay_e_pix_bb.sql`.

### painel_recebimento_resumo
- Tipo: painel / view agregada
- Uso: `vendas.html` (KPIs do topo)
- Propósito: resumo geral de faturamento por mês.
- Colunas importantes:
  - `ano_mes`
  - `mes`
  - `recebido_total`
  - `qtd_transacoes`
  - `ticket_transacao`
- **Tem que bater com `venda_diaria` mês a mês** — é o mesmo faturamento visto
  por outro caminho. Soma `recebimento_transacao_net` + `venda_especie` + Pix QR
  Code do BB (em D-1 do crédito, igual ao `venda_diaria`). Conferido nos 19 meses.
- `qtd_transacoes` e `ticket_transacao` cobrem só os canais transacionais: a
  espécie entra no total e fica fora do denominador, porque não tem contagem de
  pagamentos.

### painel_recebimento_canal
- Tipo: painel / view agregada
- Uso: `vendas.html` (donut "De onde vem o faturamento")
- Propósito: faturamento por canal de pagamento.
- Colunas importantes:
  - `ano_mes`
  - `canal`
  - `valor`
  - `qtd`
- Os rótulos ficam como cada fonte os escreve (`Credito` da Stone, `Crédito à
  vista` da Fundopay). O `normCanal` de `vendas.html` casa por trecho e funde os
  dois na mesma fatia, então a origem não se perde e o gráfico continua com uma
  fatia por canal.

### painel_recebimento_hora
- Tipo: painel / view agregada
- Uso: `vendas.html` e `app_gerente_movimento_hora`
- Propósito: faturamento por hora para análise intra-dia.
- Colunas importantes:
  - `ano_mes`
  - `hora`
  - `valor`
  - `qtd`
- Lê **apenas** `recebimento_transacao_net`. O Pix QR Code do BB fica de fora
  porque o extrato não traz o horário da venda (~R$ 475/mês; a curva segue
  representativa). Por isso esta view **não** fecha com o `painel_recebimento_resumo`.

> **Ao mexer em `venda_diaria`, mexa também nestas três.** Elas não derivam do
> `venda_diaria` — montam o faturamento por conta própria a partir das raws,
> então não herdam canal novo. Foi assim que Fundopay e Pix QR Code entraram no
> planejamento e ficaram de fora do KPI de `vendas.html`, deixando a mesma página
> com dois números diferentes (fev/2026: 118.077,57 no KPI x 134.084,59 no
> gráfico diário). Corrigido em `20260777000000`.

### importar_csv_stone(text, jsonb, boolean)
- Tipo: RPC de escrita `SECURITY DEFINER`, protegida pela permissão de `importar.html`.
- Uso: `importar.html` (rotina "Importar dados").
- Propósito: carregar as fontes Stone (`stone_extrato`, `stone_vendas`,
  `stone_recebiveis`), Banco do Brasil (`bb`) e BS Cash (`bs_cash`) pelo site,
  sem depender dos scripts Python locais — de qualquer computador ou celular.
- O navegador só lê o CSV e faz o parse em objetos por cabeçalho; validação,
  conversão, dedup, recálculo de saldo e `log_carga` acontecem nesta RPC, que é
  a autoridade. Grava nas mesmas tabelas `raw_stone_*`, com as mesmas chaves de
  dedup dos scripts (`uq_extrato_dedup`, `uq_vendas_stoneid`,
  `uq_receb_stoneid_parcela`), então os dois caminhos convivem e reenviar um
  arquivo não duplica.
- `p_dry_run = true` valida e devolve o resumo (linhas, novas, período) sem
  gravar — é o que alimenta a tela de conferência. Como é o mesmo código do
  caminho real, o preview não diverge da gravação.
- Tolerância zero a rejeição, igual ao Python: qualquer linha inválida aborta o
  arquivo inteiro. Limite de 20.000 linhas por chamada; cargas históricas
  grandes continuam no caminho Python.
- Parse delegado a `private.parse_stone_extrato/vendas/recebiveis(jsonb)` e aos
  helpers `private.campo_csv`, `private.parse_valor_br`,
  `private.parse_data_hora_br`, `private.parse_inteiro_br`, que espelham
  `scripts/importacao/importacao_core.py`. Os equivalentes foram conferidos caso
  a caso contra as funções reais do Python.
- O recálculo e o refresh ficam fora da transação de gravação. Desde
  `20260758000000`, `solicitar_recalculo_saldo()` enfileira o período e um job
  `pg_cron` executa `recalcular_saldo_fechamento()` + `refresh_painel()` em
  background, fora do `statement_timeout` curto de `authenticated`.
- Criada em `20260751000000_importacao_web_stone.sql`.

### solicitar_recalculo_saldo(date, date) / consultar_recalculo_saldo(bigint)
- Tipo: RPCs `SECURITY DEFINER`, protegidas pela permissão de `importar.html`.
- Uso: `importar.html`, `status.html`.
- Propósito: enfileirar e acompanhar o recálculo assíncrono do saldo depois de
  uma importação ou manutenção. A fila privada guarda somente período, estado
  e mensagem técnica. Não há cron permanente: cada solicitação liga
  temporariamente `sirfisher-processar-recalculo-saldo`, que processa uma
  tarefa por vez, atualiza os snapshots e remove o próprio agendamento quando a
  fila esvazia. A migration inicial enfileira uma recomposição desde o começo
  do ano para recuperar automaticamente dados já gravados antes da correção.
- Criadas em `20260758000000_recalculo_saldo_assincrono.sql`; agendamento
  convertido para sob demanda em
  `20260759000000_recalculo_saldo_cron_sob_demanda.sql`.

## Tabelas / views que alimentam os painéis HTML
- `analise_individual` → `analise_individual.html`
- `categoria_dre` → `analise_individual.html`, `classificar_excecoes.html`
- `ajuste_manual` → estado atual dos ajustes feitos em `analise_individual.html`
- `painel_saldo_atual` → `caixa.html`, `index.html`
- `painel_saldo_fim_mes` → `caixa.html`, `index.html`
- `painel_fluxo_caixa` → `caixa.html`
- `recebimento_conhecido` → `caixa.html`
- `recebimento_projetado` → `caixa.html`
- `projecao_despesa_fixa` → `caixa.html`
- `projecao_despesa_direta` → `caixa.html`
- `painel_ultima_carga` → `caixa.html`, `dre.html`, `index.html`, `vendas.html`
- `painel_cargas` → `caixa.html`, `dre.html`, `index.html`, `vendas.html`
- `painel_saldo_por_conta` → `caixa.html`
- `excecoes` → `classificar_excecoes.html`
- `de_para` → estado atual das regras criadas em `classificar_excecoes.html`
- `app_classificacoes_recentes` → correção e desfazer nas duas páginas de classificação
- `painel_dre_cascata` → `dre.html`
- `painel_resumo_mensal` → `index.html`, `vendas.html`
- `painel_composicao_despesa` → `index.html`
- `painel_margem_contribuicao` → `index.html`
- `painel_diario` → `index.html`, `vendas.html`
- `mv_saldo_caixa_diario_detalhado` / `detalhar_saldo_caixa_dia(date)` → saldo
  realizado e memória por conta de `calendario.html`
- `listar_calendario_financeiro(date)` → `calendario.html`
- `listar_despesas_dia(date)` → `calendario.html`
- `venda_especie` → `venda_especie.html`
- `conta_recorrente` / `conta_recorrente_pagamento` → `contas_recorrentes.html`
- `app_contas_recorrentes_pagamentos` / `app_contas_recorrentes_totais` → histórico e gráfico de `contas_recorrentes.html`
- `painel_recebimento_resumo` → `vendas.html`
- `painel_recebimento_canal` → `vendas.html`
- `painel_recebimento_hora` → `vendas.html`
- `importar_csv_stone(text, jsonb, boolean)` → `importar.html`
- `raw_stone_extrato` / `raw_stone_vendas` / `raw_stone_recebiveis` → destino da
  carga, tanto pelo `importar.html` quanto pelos scripts de `scripts/importacao/`

## Observações
- O front-end autenticado usa views `app_*` e RPCs protegidas; tabelas internas
  não são expostas para leitura anônima.
- Esse documento não altera o banco, apenas descreve o schema usado pelo app.

