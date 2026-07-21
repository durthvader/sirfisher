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
- Colunas importantes:
  - `data_ref`
  - `saldo_atual`
  - `data_comp`
  - `saldo_comp`

### painel_saldo_fim_mes
- Tipo: painel / view agregada
- Uso: `caixa.html`, `index.html`
- Propósito: dados de saldo no final do mês para histórico e projeção.
- Colunas importantes:
  - `mes`
  - `ano_mes`
  - `saldo_fim`
  - `situacao`

### painel_fluxo_caixa
- Tipo: painel / view agregada
- Uso: `caixa.html`
- Propósito: mostra fluxo de caixa diário, saldo real/projetado e entradas/saídas.
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
- Propósito: mostra projeção de despesas fixas por dia. Calcula a média mensal dos 3 meses fechados anteriores (débitos dos grupos DRE PESSOAL, INFRAESTRUTURA, MARKETING E PUBLICIDADE e IMPOSTOS em `fato_financeiro`), subtrai o realizado na mesma fonte e nos mesmos grupos e distribui o restante (nunca negativo) pelos dias do mês após o corte de caixa. Meses futuros sem realizado projetam a média cheia. Redefinida em `20260757000000_corrige_colchao_despesa_fixa.sql`.
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

### listar_calendario_financeiro(date)
- Tipo: RPC mensal `SECURITY DEFINER`, protegida pela permissão de `calendario.html`.
- Uso: `calendario.html`.
- Propósito: consolidar, por dia, meta e faturamento acumulados, vendas por
  forma, recebimentos, despesas recorrentes/não recorrentes e saldo de caixa.
- O realizado reutiliza as fontes dos painéis existentes. Depois do corte das
  cargas, a RPC usa as projeções de venda, recebimento, despesa e saldo já
  adotadas em `caixa.html`.
- O total de despesas realizadas vem de `fato_financeiro`. A parcela recorrente
  usa pagamentos de `conta_recorrente_pagamento` limitada ao total financeiro
  do dia; o restante é apresentado como não recorrente. Diferenças ficam
  expostas em `despesa_recorrente_nao_conciliada`, sem alterar a origem.

### listar_despesas_dia(date)
- Tipo: RPC diária `SECURITY DEFINER`, protegida pela permissão de `calendario.html`.
- Uso: popover de despesas de `calendario.html`, carregada sob demanda (com cache por dia).
- Propósito: listar as despesas individuais de um dia realizado (descrição, categoria, valor).
- Mesmo recorte da CTE `despesas_reais` de `listar_calendario_financeiro`
  (`fato_financeiro` por `data_caixa`, Débito, `entra_dre`, empresas PRAIA/BB),
  para a soma da lista bater com a coluna Despesas.
- Criada em `20260737000000_listar_despesas_dia.sql`.

### venda_especie
- Tipo: tabela de vendas por espécie
- Uso: `venda_especie.html`
- Propósito: registra vendas por tipo de transação ou espécie.
- Colunas importantes:
  - `id`
  - `data`
  - `unidade`
  - `valor`
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
  - `observacao`
  - `criado_em`

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

### painel_recebimento_resumo
- Tipo: painel / view agregada
- Uso: `vendas.html`
- Propósito: resumo geral de recebimento por mês.
- Colunas importantes:
  - `ano_mes`
  - `mes`
  - `recebido_total`
  - `qtd_transacoes`
  - `ticket_transacao`

### painel_recebimento_canal
- Tipo: painel / view agregada
- Uso: `vendas.html`
- Propósito: recebido por canal de pagamento.
- Colunas importantes:
  - `ano_mes`
  - `canal`
  - `valor`
  - `qtd`

### painel_recebimento_hora
- Tipo: painel / view agregada
- Uso: `vendas.html`
- Propósito: recebimentos por hora para análise intra-dia.
- Colunas importantes:
  - `ano_mes`
  - `hora`
  - `valor`
  - `qtd`

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
  e mensagem técnica. O job `sirfisher-processar-recalculo-saldo` processa uma
  tarefa por vez a cada 10 segundos e atualiza os snapshots ao concluir. A
  migration inicial enfileira uma recomposição desde o começo do ano para
  recuperar automaticamente dados já gravados antes da correção.
- Criadas/redefinidas em `20260758000000_recalculo_saldo_assincrono.sql`.

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

