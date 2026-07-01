# Supabase Schema - Projeto Sir Fisher App

## Visão geral
Este documento resume o schema público do Supabase usado pelo painel Sir Fisher App. O resumo foi feito com base nas tabelas/vistas acessadas pelos arquivos HTML do projeto e nas respostas do endpoint REST público com a role anon.

> Importante: não foram feitas alterações no banco de dados. A análise é apenas de leitura.

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
- Uso: `caixa.html`
- Propósito: mostra projeção de despesas fixas por dia.
- Colunas importantes:
  - `dia`
  - `valor`

### projecao_despesa_direta
- Tipo: painel / view agregada
- Uso: `caixa.html`
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

### painel_dre_cascata
- Tipo: painel / view agregada
- Uso: `dre.html`
- Propósito: fornece a cascata DRE mensal com receita, CMV, despesas e resultado líquido.
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

## Tabelas / views que alimentam os painéis HTML
- `analise_individual` → `analise_individual.html`
- `categoria_dre` → `analise_individual.html`, `classificar_excecoes.html`
- `ajuste_manual` → gravação via `analise_individual.html`
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
- `de_para` → `classificar_excecoes.html` (insert only)
- `painel_dre_cascata` → `dre.html`
- `painel_resumo_mensal` → `index.html`, `vendas.html`
- `painel_composicao_despesa` → `index.html`
- `painel_margem_contribuicao` → `index.html`
- `painel_diario` → `index.html`, `vendas.html`
- `venda_especie` → `venda_especie.html`
- `painel_recebimento_resumo` → `vendas.html`
- `painel_recebimento_canal` → `vendas.html`
- `painel_recebimento_hora` → `vendas.html`

## Observações
- A tabela `de_para` não é legível pela role `anon` atual: `permission denied for table de_para`.
- Todas as demais tabelas/views listadas foram acessadas com sucesso e retornaram colunas e dados.
- Esse documento não altera o banco, apenas descreve o schema público usado pelo app.

