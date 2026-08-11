# Supabase Schema - Projeto Sir Fisher App

## Visão geral
Este documento resume o schema público do Supabase usado pelo painel Sir Fisher
App. O conteúdo acompanha os contratos do front-end e as migrations versionadas
no repositório.

## Autorização dos endpoints

- O front-end usa `public.app_*` e RPCs, sem acesso anônimo aos dados
  financeiros.
- O padrão intencional das views continua
  `security_barrier = true, security_invoker = false`, com `select` apenas para
  `authenticated`.
- Desde `20260788000000`, o gate das views, RPCs operacionais e policies
  ligadas às páginas configuráveis consulta `public.pagina_permissao` no
  servidor. O bloqueio de `assets/auth.js` é apenas a primeira camada.
- `public.usuario_pode_acessar_alguma_pagina(text[])` atende endpoints
  compartilhados. Admin continua irrestrito; os demais usuários precisam ter
  perfil ativo e o papel liberado em ao menos uma página informada.
- Endpoints administrativos (`usuarios.html`, `status.html` e
  `permissoes.html`) continuam exclusivos de admin.

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
- Uso: alimenta `analise_individual.html`, `classificar_excecoes.html` e
  `transacoes_dia.html`
- Propósito: define categorias e grupos DRE para classificação das transações.
- Colunas importantes:
  - `categoria`
  - `dre_grupo`
  - `natureza`

### ajuste_manual
- Tipo: tabela de ajustes manuais
- Uso: `analise_individual.html` e `transacoes_dia.html`, por meio das RPCs de
  classificação
- Propósito: registra classificações manuais que foram aplicadas a transações emergenciais.
- Segurança: a leitura direta por RLS continua ligada a
  `analise_individual.html`, mas `authenticated` não possui `INSERT`, `UPDATE`
  nem `DELETE` direto. Todas as alterações passam por RPCs `SECURITY DEFINER`
  com o gate da página correspondente; nenhuma das duas páginas recebe acesso
  irrestrito à tabela.
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
- Uso: `caixa.html`, `dre.html`, `index.html`, `despesas.html`
- Propósito: mostra projeção de despesas fixas por dia. Calcula a média mensal dos 3 meses fechados anteriores (débitos dos grupos DRE PESSOAL, INFRAESTRUTURA, MARKETING E PUBLICIDADE e IMPOSTOS em `fato_financeiro`), subtrai o realizado na mesma fonte e nos mesmos grupos e distribui o restante (nunca negativo) pelos dias do mês após o corte de caixa. Contas recorrentes ativas, do tipo despesa, marcadas para entrar nos totais, com média positiva e ainda sem pagamento na competência entram no vencimento como previsão explícita; seu valor reduz antes o colchão genérico para evitar dupla contagem. Meses futuros sem realizado projetam a média cheia. Redefinida em `20260760000000_previsao_contas_abertas_no_caixa.sql`.
- Colunas importantes:
  - `dia`
  - `valor`

### projecao_despesa_direta
- Tipo: painel / view agregada
- Uso: `caixa.html`, `dre.html`, `index.html`, `despesas.html`
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
- Uso: `classificar_excecoes.html` para inserir novas regras e
  `gerenciador_de_para.html` para procurar, editar, ativar, desativar e
  restaurar regras existentes
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
- Desde `20260811000000`, `authenticated` não possui DML direto nem acesso à
  sequence de `de_para`. Todas as mudanças passam pelas RPCs protegidas e pelo
  trigger de auditoria. A chave `(chave_tipo, chave_valor)` fica imutável na
  rotina; a remoção operacional é uma desativação, preservando a identidade e
  o histórico.
- A alteração é retroativa apenas nas fontes vivas usadas por
  `fato_financeiro` e vale para importações futuras. `raw_historico` continua
  congelado: `sincronizar_historico_de_para()` não é chamado automaticamente.
  `ajuste_manual` mantém precedência sobre a categoria da regra.

### Gerenciador De/Para
- Criado em `20260811000000_gerenciador_de_para.sql` para
  `gerenciador_de_para.html`, com permissão de página independente e seed
  inicial para `socio`.
- `app_gerenciador_de_para` expõe o estado atual e um token calculado sobre a
  versão exata da regra. `listar_regras_de_para(...)` oferece busca server-side
  por apelido, chave original/CNPJ ou categoria, filtros e paginação explícita.
- `prever_alteracao_de_para(...)` faz duas leituras do `fato_financeiro`
  canônico dentro da mesma transação. A função aplica a proposta em uma
  subtransação e força seu rollback depois da segunda fotografia; assim a
  prévia respeita CNPJ antes de nome, regras especiais por origem e tipo e
  ajustes individuais, sem persistir a simulação nem duplicar o grande `CASE`
  classificatório. O retorno separa classificações, rótulos, entradas, saídas,
  período e transições.
- `salvar_regra_de_para(...)` exige o mesmo token revisado na prévia, mantém a
  chave imutável e altera somente apelido, categoria e situação. O apelido é
  obrigatório para evitar fornecedor em branco nos relatórios. Conflitos de
  edição concorrente falham sem sobrescrever o estado mais novo. A confirmação
  recalcula a fotografia de impacto e também falha se lançamentos ou ajustes
  mudaram depois da revisão feita pelo usuário.
- `private.de_para_historico` recebe INSERT/UPDATE/DELETE por trigger, inclusive
  quando a mudança nasce nas RPCs antigas de `classificar_excecoes.html`. A
  view `app_gerenciador_de_para_historico` mostra os snapshots e libera
  `desfazer_regra_de_para(bigint)` somente para o último evento ainda compatível.
  Desfazer uma criação restaura exatamente a inexistência anterior da linha; é
  a única exclusão física do fluxo e ocorre sob lock, vinculada ao evento
  auditado. Alterações normais continuam usando ativação/desativação.
- Salvar ou desfazer chama `private.agendar_refresh_classificacoes(date)`: a
  mudança aparece imediatamente no fato normal e as materialized views são
  atualizadas pela fila assíncrona já existente.

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
- Propósito: listar o estado atual das classificações antigas. O ramo
  individual continua sendo usado por `analise_individual.html`; a edição de
  regras por fornecedor foi movida para `gerenciador_de_para.html`.
- A view combina registros ativos de `de_para` e `ajuste_manual`. Ajustes que
  pertencem a um `estorno_confirmado` ativo ficam fora do ramo individual,
  porque são gerenciados exclusivamente pela conciliação contábil.
- RPCs disponíveis:
  - `classificar_excecao(text, text, text, text)`;
  - `classificar_transacao(text, bigint, text)`;
  - `corrigir_classificacao(text, bigint, text)`;
  - `desfazer_classificacao(text, bigint)`.
- Todas validam a permissão da página correspondente. Desde `20260811000000`,
  alterações do ramo `excecao` entram em `private.de_para_historico` e desfazer
  pela fila restaura apenas o evento do próprio usuário, criado nos últimos 10
  minutos e ainda compatível. O gerenciador desfaz pelo ID exato do histórico;
  o ramo individual mantém seu comportamento anterior.

### Revisão diária das classificações
- Criada em `20260810000000_revisao_diaria_transacoes.sql` para
  `transacoes_dia.html`.
- `app_transacoes_dia` expõe os lançamentos de `fato_financeiro` por
  `data_caixa`, com categoria final, grupo DRE, situação e origem da
  classificação (`manual`, `automatica`, `base_historica` ou `pendente`). A
  identidade continua sendo o par `(origem, raw_id)`. O documento da
  contraparte não é exposto porque a rotina não o utiliza.
- A edição altera somente `ajuste_manual`. Valor, data, contraparte,
  movimentação e tabelas `raw_*` permanecem imutáveis. Restaurar remove o
  override e volta para a regra/base vigente, que também pode resultar em uma
  pendência.
- `private.transacao_classificacao_historico` guarda autor, horário, categoria
  final e estado completo do ajuste antes/depois. Não há acesso direto; a view
  protegida `app_transacoes_dia_historico` exibe o histórico usando
  `private.nome_exibicao_usuario(uuid)` e indica quando o desfazer ainda é
  compatível com o estado atual.
- RPCs `SECURITY DEFINER`, todas protegidas pela permissão configurável de
  `transacoes_dia.html`:
  - `salvar_classificacao_transacao_dia(...)`;
  - `restaurar_classificacao_transacao_dia(...)`;
  - `desfazer_classificacao_transacao_dia(bigint)`.
- As RPCs usam comparação otimista de categoria, timestamp e observação para
  recusar uma tela desatualizada; a observação não sai na Data API, somente um
  token de comparação. `ANALISAR INDIVIDUAL` não é aceita como categoria final
  nesta rotina. Mudanças seguidas compartilham uma tarefa `somente_refresh`
  pendente; o worker atualiza as materialized views em segundo plano sem
  recalcular saldo e sem segurar a resposta do navegador.
- Uma ponta coberta por decisão ativa de `estorno_confirmado` fica bloqueada em
  qualquer caminho de escrita. Constraint triggers diferidos validam no fim da
  transação que ambas as pontas continuam como `estornado`, sem impedir que a
  própria conciliação confirme ou desfaça as duas alterações atomicamente. A
  decisão deve ser desfeita primeiro em `conciliacao_contabil.html`. Antes de
  instalar os triggers, a migration valida as decisões já ativas e interrompe
  com erro explícito se encontrar alguma inconsistência; não há correção
  silenciosa de classificação financeira.

### painel_dre_cascata
- Tipo: painel / view agregada
- Uso: `dre.html`
- Propósito: fornece a cascata DRE mensal realizada com receita, CMV, despesas e resultado líquido. No mês aberto, `dre.html` usa como receita de fechamento a mesma tendência de faturamento bruto do Resumo; soma ao resultado operacional realizado a diferença entre essa projeção e a receita já reconhecida, desconta as despesas diretas e fixas futuras das mesmas views usadas pelo Caixa e mantém os itens abaixo da operação pelo realizado. Isso evita extrapolar a receita financeira ainda incompleta no começo do mês enquanto as despesas já usam a venda bruta e o mês cheio.
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

### app_gerente_dre_cascata_perc
- Tipo: view protegida de leitura
- Uso: `gerente.html`
- Propósito: expõe a cascata DRE realizada somente em percentuais e, em
  colunas separadas, os percentuais projetados de resultado operacional e
  líquido. A cascata permanece realizada; a projeção usa a mesma equação de
  fechamento de `index.html` e `dre.html`.
- Segurança: `security_barrier = true`, `security_invoker = false`, gate
  server-side da página `gerente.html`, com `select` apenas para
  `authenticated`.
- Colunas adicionais criadas em
  `20260785000000_gerente_resultado_realizado_projetado.sql`:
  - `resultado_operacional_projetado_perc`
  - `resultado_liquido_projetado_perc`
  - `em_projecao`

### app_gerente_saldo_variacao
- Tipo: view protegida de leitura
- Uso: `gerente.html`
- Propósito: compara o saldo final do mês com o fechamento do mês anterior.
  Meses fechados usam o último snapshot histórico; o mês aberto usa o saldo
  projetado.
- Segurança: mantém o padrão das views `app_*` e não expõe os saldos
  absolutos. A bonificação permite inferir a variação em reais ao dividi-la
  por 2%, risco aceito para atender ao card solicitado.
- Colunas:
  - `ano_mes`
  - `variacao_perc`
  - `previsao_bonificacao`:
    `mínimo(máximo(saldo_fim − saldo_anterior, 0) × 0,02, R$ 600,00)`;
    queda do caixa resulta em `R$ 0,00` e o valor nunca supera `R$ 600,00`.

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

### stone_estabelecimento — o painel é de UMA unidade
- Tipo: tabela de mapeamento (`stonecode` → `unidade`)
- **O grupo tem três casas com stonecodes distintos:** `770398216` Praia (a
  unidade do painel), `140366173` Imprensa e `916046432` PUB. O `173835323` é um
  segundo código da **própria Praia** (e-commerce / link de pagamento) — provado
  por aparecer dentro dos arquivos exportados da Praia.
- **O relatório da Stone é por estabelecimento.** Importar o arquivo da casa
  errada mistura o faturamento: aconteceu em 28/06/2026 e R$ 25.135,94 de
  Imprensa e PUB contaram como Praia entre dez/2025 e mai/2026.
- **Filtrar por stonecode não basta:** as linhas de **Pix QRcode não trazem
  stonecode**, só as de cartão. A resolução usa o **número de série do
  terminal** — conferido que cada série pertence a um único stonecode e nenhuma
  migrou entre unidades, então a série identifica a unidade também no Pix.
- O filtro em `recebimento_stone_net` **exclui o que se sabe ser de outra
  unidade**, em vez de incluir só o que se sabe ser Praia. Assim um terminal novo
  da Praia conta desde o primeiro dia, mesmo antes de entrar nesta tabela.
- Os importadores `02_` e `03_` avisam quando o arquivo traz outro
  estabelecimento. A lista canônica é esta tabela; `STONECODES_PAINEL` em
  `importacao_core.py` existe só para o aviso rodar em `--dry-run`, sem banco.
- Criada em `20260781000000`; e-commerce registrado em `20260782000000`.
- RLS habilitado em `20260789000000`, sem policy para clientes. `anon`,
  `authenticated` e `PUBLIC` não têm privilégios diretos; views e RPCs
  proprietárias continuam usando o mapeamento internamente.

### raw_fundopay_vendas / venda_diaria
- `venda_diaria` é a base do faturamento (planejamento, vendas.html, metas,
  tendência, peso do dia e, por `projecao_venda_diaria`, a projeção de caixa).
- O braço da Stone lê o **`recebimento_stone_net`**, não a tabela crua: é ali que
  moram, num lugar só, o líquido de cancelamento e o filtro de unidade. As duas
  expressões eram idênticas e duplicadas — foi assim que os dois caminhos do
  faturamento divergiram na 20260777000000.
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
- Em `raw_bb`, os débitos `Aplicação Fundo BB` e `BB RF LP Selic` usam uma
  identidade canônica por data e valor. O BB altera rótulo e documento quando
  consolida a aplicação; usar o hash literal fazia uma reexportação contar o
  mesmo movimento duas vezes. A correção e a limpeza pontual estão na migration
  `20260801000000_bb_fundo_nao_duplica_reexportacao.sql`.
- A mesma migration passou a validar cada extrato BB pela equação `Saldo
  Anterior + movimentos = S A L D O`. As linhas de saldo continuam fora de
  `fato_financeiro`, mas deixam de ser descartadas antes de comprovar a
  integridade do arquivo; ausência, valor inválido ou diferença rejeitam a
  carga inteira nos caminhos web e Python.
- Na importação web, `private.parse_bb` ainda reconstrói o saldo BB pela mesma
  âncora usada no painel, soma somente os hashes novos do arquivo e compara o
  resultado ao `S A L D O` do extrato. A carga é rejeitada antes do `INSERT` se
  o arquivo fechar internamente, mas divergir do saldo que o painel exibiria.
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
- O `fato_financeiro` classifica em duas etapas: primeiro encontra o `de_para`
  pelo nome da contraparte e depois aplica regras por **tipo de lançamento**
  específicas de cada origem. Em geral, o `de_para` tem precedência, com duas
  exceções Stone documentadas em
  `20260803000000_creditos_stone_por_tipo_e_analise.sql`:
  - crédito `Transação` é venda e usa `Transação`/`RECEITAS`, mesmo quando o
    pagador também possui categoria de despesa nos pagamentos;
  - crédito `Pix` que herdaria uma categoria de natureza `Despesa` não é
    adivinhado como venda nem mantido automaticamente como redução da despesa:
    vai para `Análise individual`, onde pode ser marcado como receita,
    devolução/reembolso, transferência ou entrada não operacional.
  Transferências próprias, fornecedores explicitamente marcados para análise
  individual e ajustes manuais preservam precedência. Débitos continuam
  seguindo normalmente o `de_para`.
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
  - `Pix-Envio devolvido` e `Pix-Recebimento devolvido` → estornado
- Ficam fora de propósito os tipos cuja categoria não é determinada pelo tipo:
  `Pix - Enviado`, `Pagamento de Boleto` (já virou Aluguel, Gás e Plano
  Dentário em casos distintos) e `Pagamento de Impostos`.

### Conciliação contábil
- A rotina `conciliacao_contabil.html` separa categorias que **devem possuir
  uma perna oposta** (`Transferencia entre Contas` e `estornado`) de movimentos
  apenas informativos (`Cartão BB`, `cartão BNB`,
  `Cartão BTG`, `Depósito Dinheiro`, `Antecipação de Receita` e
  `ANALISAR INDIVIDUAL`). Portanto, não se espera que todo o universo de
  natureza `Contabil` some zero.
- `mv_conciliacao_contabil` procura uma transação de sinal oposto, mesmo valor
  absoluto (tolerância de R$ 0,01) e distância máxima de cinco dias. O status é
  `conciliado`, `classificacao_divergente`, `ambiguo`, `sem_contrapartida` ou
  `informativo`. O pareamento é diagnóstico e nunca altera lançamentos.
- Desde `20260805000000_detecta_estornos_por_tempo_e_contraparte.sql`, a mesma
  MV também procura possíveis estornos entre categorias operacionais. A regra
  exige débito seguido de crédito de mesmo valor, na mesma conta e no mesmo
  dia. Par único com contraparte/documento ou texto bancário compatível recebe
  `estorno_forte` quando ocorre em até 60 minutos e `estorno_provavel` nos
  demais casos; coincidência ambígua ou sem evidência suficiente recebe
  `estorno_analise`. A detecção apenas abre uma revisão e não cria
  `ajuste_manual`.
- Stone, BS Cash e a base histórica preservam `data_hora`. BB e Inter fornecem
  apenas a data, por isso nunca recebem o nível forte. Nesses bancos, valor,
  conta, data, contraparte e descrição sustentam somente o nível provável ou
  de análise.
- `app_conciliacao_contabil` expõe o detalhe autorizado, sem documentos de
  contraparte; `app_conciliacao_contabil_resumo_mensal` entrega os totais por
  mês/status. Ambas usam o gate configurável de
  `conciliacao_contabil.html`, inicialmente liberado apenas para `socio` (além
  de `admin`, que sempre tem acesso).
- A materialized view entra no ciclo de `refresh_painel()`. Isso evita refazer
  o pareamento pesado a cada abertura da página; os dados são atualizados ao
  fim das importações ou pelo comando administrativo de atualização do painel.
- Desde `20260806000000_unifica_devolucao_como_estorno.sql`, pagamentos
  devolvidos, cancelamentos e reversões usam somente a categoria canônica
  `estornado`. A categoria antiga `pagamento devolvido` foi convertida nos
  ajustes, regras e histórico, removida das opções do portal e deixou de ser
  produzida pela classificação automática do BB. O efeito financeiro não
  mudou: continua `CONTABIL`, fora da DRE e com expectativa de saldo zero.
- Desde `20260807000000_acoes_conciliacao_contabil.sql`, a rotina deixou de ser
  somente leitura. `decidir_conciliacao_contabil(...)` confirma as duas pontas
  como `estornado` na mesma transação ou registra que o par não é relacionado.
  `desfazer_decisao_conciliacao_contabil(bigint)` restaura os ajustes manuais
  anteriores e impede desfazer silenciosamente se uma ponta tiver sido alterada
  depois da confirmação. As duas RPCs usam o gate configurável da própria
  página.
- `conciliacao_contabil_decisao` mantém o histórico com usuário, data, pontas,
  valores, categorias anteriores e estado ativo/desfeito. A tabela tem RLS e
  não possui grants diretos; o acesso ocorre pelas RPCs e pela view protegida
  `app_conciliacao_contabil_decisoes`. As views de detalhe e resumo aplicam as
  decisões ativas aos status `estorno_confirmado` e `descartado`.
- Os avisos do Security Advisor `rls_enabled_no_policy` para essa tabela e
  `authenticated_security_definer_function_executable` para as duas RPCs são
  intencionais. RLS sem policy nega acesso direto, enquanto `SECURITY DEFINER`
  permite atualizar as duas pontas atomicamente; ambas as funções verificam
  `usuario_pode_acessar_pagina('conciliacao_contabil.html')`, usam `search_path`
  fixo e não concedem execução a `anon`/`public`.
- `20260808000000_conciliacao_estorno_assincrona.sql` remove o
  `refresh materialized view` da transação do navegador. Confirmar/desfazer
  grava a decisão e os dois ajustes rapidamente, acrescenta uma tarefa
  `somente_refresh` à fila já processada pelo `pg_cron` e responde antes do
  trabalho pesado. O worker pula o recálculo de saldo nesse tipo de tarefa e
  executa apenas `refresh_painel()`. A view de detalhe sobrepõe categoria/status
  da decisão ativa para a confirmação aparecer imediatamente.

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

### Conferência do depósito em espécie

- Criada em `20260812000000_conferencia_deposito_especie.sql` para o painel
  "Conferência com o Banco do Brasil" em `venda_especie.html`.
- Regra de negócio confirmada com o usuário: **100% do dinheiro em espécie
  recolhido no quiosque é depositado no BB**, então todo lançamento
  `Dep dinheiro%` de `raw_bb` corresponde a sangria. É isso que torna o saldo
  acumulado o controle mais forte — ele independe de acertar de qual dia veio
  cada nota.
- O casamento é **por lote, não 1:1 por sangria**: várias sangrias são marcadas
  como depositadas na mesma sessão (uma ida ao caixa eletrônico) e o mesmo
  dinheiro entra no extrato fatiado em vários envelopes, por causa do limite do
  ATM. O lote é detectado por intervalo maior que 10 minutos entre marcações
  consecutivas de `depositada_em`.
- Cada lançamento do extrato entra em um único lote: o mais próximo dentro da
  janela D−1 a D+2, resolvido por `distinct on` para não contar o mesmo
  lançamento duas vezes. A janela cobre depósito noturno creditado no dia
  seguinte e marcação feita alguns dias depois da ida ao banco.
- **Data de corte `2026-07-21`** em todas as views: antes disso `depositada_em`
  é carimbo do backfill de `20260718000000`, que preencheu o campo com a própria
  data da sangria para fechar o ciclo dos registros antigos. Sem o corte a tela
  mostraria centenas de divergências falsas e perderia a serventia de alarme.
- `app_conferencia_deposito_especie_resumo` é o alarme: `marcado − extrato −
  justificativas`. Também expõe `extrato_ate`, porque sem essa data um depósito
  recente aparece como "não chegou no banco" quando o atrasado é o extrato.
- `app_conferencia_deposito_especie` é o localizador, um registro por lote, com
  status `conferido`, `falta_no_banco`, `sobra_no_banco`, `sem_extrato` e
  `sem_lote`. O último marca dinheiro que entrou no BB sem sangria marcada.
- `conferencia_deposito_ajuste` guarda as justificativas de divergência, com
  motivo obrigatório, autor e momento. Sem essa válvula uma diferença explicada
  ficaria no acumulado para sempre, o painel viveria vermelho e o alarme
  deixaria de alarmar. Convenção de sinal: valor positivo explica marcado que
  não entrou no BB; negativo explica entrada no BB sem sangria marcada.
- Escrita apenas por `registrar_ajuste_conferencia_deposito(date, numeric, text)`
  e `desfazer_ajuste_conferencia_deposito(bigint)`, ambas validando
  `usuario_pode_acessar_pagina('venda_especie.html')`. A tabela tem RLS ligado
  sem policy (nega tudo por padrão) e `authenticated` não possui DML direto.
  Desfazer preserva a linha e registra quem desfez: nada de exclusão física em
  trilha de auditoria.
- `min(uuid)` não existe no Postgres 17; o responsável do lote sai de
  `(array_agg(depositada_por order by depositada_em))[1]`.
- A conferência é somente leitura sobre `venda_especie` e `raw_bb`: não altera
  sangria, não gera lançamento financeiro e não dispara refresh de materialized
  view.

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
- `categoria_dre` → `analise_individual.html`, `classificar_excecoes.html`,
  `transacoes_dia.html`, `gerenciador_de_para.html`
- `ajuste_manual` → estado atual dos ajustes feitos em
  `analise_individual.html` e `transacoes_dia.html`
- `app_transacoes_dia` / `app_transacoes_dia_historico` → conferência e
  histórico de `transacoes_dia.html`
- `painel_saldo_atual` → `caixa.html`, `index.html`
- `painel_saldo_fim_mes` → `caixa.html`, `index.html`
- `painel_fluxo_caixa` → `caixa.html`
- `recebimento_conhecido` → `caixa.html`
- `recebimento_projetado` → `caixa.html`
- `projecao_despesa_fixa` → `caixa.html`, `dre.html`, `index.html`, `despesas.html`
- `projecao_despesa_direta` → `caixa.html`, `dre.html`, `index.html`, `despesas.html`
- `painel_ultima_carga` → `caixa.html`, `dre.html`, `index.html`, `vendas.html`
- `painel_cargas` → `caixa.html`, `dre.html`, `index.html`, `vendas.html`
- `painel_saldo_por_conta` → `caixa.html`
- `excecoes` → `classificar_excecoes.html`
- `de_para` → estado atual das regras criadas em `classificar_excecoes.html` e
  mantidas em `gerenciador_de_para.html`
- `app_gerenciador_de_para` / `listar_regras_de_para(...)` → consulta das
  regras em `gerenciador_de_para.html`
- `app_gerenciador_de_para_historico` → histórico e desfazer do De/Para
- `app_classificacoes_recentes` → histórico operacional da classificação
  individual e compatibilidade com os fluxos antigos
- `painel_dre_cascata` → `dre.html`, `index.html`
- `painel_resumo_mensal` → `index.html`, `vendas.html`, `dre.html`, `despesas.html`
- `painel_composicao_despesa` → `index.html`
- `painel_margem_contribuicao` → `index.html`
- `painel_diario` → `index.html`, `vendas.html`
- `mv_saldo_caixa_diario_detalhado` / `detalhar_saldo_caixa_dia(date)` → saldo
  realizado e memória por conta de `calendario.html`
- `listar_calendario_financeiro(date)` → `calendario.html`
- `listar_despesas_dia(date)` → `calendario.html`
- `venda_especie` → `venda_especie.html`
- `app_conferencia_deposito_especie`, `app_conferencia_deposito_especie_resumo`
  e `app_conferencia_deposito_ajustes` → `venda_especie.html`
- `conta_recorrente` / `conta_recorrente_pagamento` → `contas_recorrentes.html`
- `app_contas_recorrentes_pagamentos` / `app_contas_recorrentes_totais` → histórico e gráfico de `contas_recorrentes.html`
- `painel_recebimento_resumo` → `vendas.html`
- `painel_recebimento_canal` → `vendas.html`
- `painel_recebimento_hora` → `vendas.html`
- `importar_csv_stone(text, jsonb, boolean)` → `importar.html`
- `raw_stone_extrato` / `raw_stone_vendas` / `raw_stone_recebiveis` → destino da
  carga, tanto pelo `importar.html` quanto pelos scripts de `scripts/importacao/`

### importar_csv_stone — o segundo caminho de gravação
- Tipo: função `SECURITY DEFINER`, usada por `importar.html`
- **São dois caminhos de gravação, não um:** `scripts/importacao/*.py` e esta
  função. Mexeu em restrição única, chave de dedup ou coluna obrigatória? Varra
  os dois. Trocar a chave dos recebíveis sem atualizar aqui quebrou a tela com
  *"there is no unique or exclusion constraint matching the ON CONFLICT
  specification"* (corrigido em `20260783000000`).
- Aplica as mesmas proteções do Python (`20260784000000`):
  - **STONE ID em notação científica → rejeição.** Entra na lista de motivos e
    vale a tolerância zero da função; nada é gravado. O padrão exige dígito
    antes do `E`, senão pegaria todo ID de Pix.
  - **Estabelecimento de outra unidade → aviso.** Devolve `estabelecimentos`
    (contagem por stonecode) e `outras_unidades` (o que não é Praia, incluindo
    stonecode não cadastrado). É aviso e não rejeição: o arquivo pode estar
    íntegro e ser de outra casa, e as views já filtram por unidade.
- **Limite de 20.000 linhas** por arquivo; acima disso levanta exceção pedindo o
  script local. É a única diferença funcional entre os dois caminhos.
- Ao alterar esta função, gere o `CREATE OR REPLACE` a partir de
  `pg_get_functiondef` e substitua trechos âncora por script, abortando se algum
  não casar exatamente uma vez — ela tem ~200 linhas e transcrever à mão convida
  a diferença silenciosa.

### raw_stone_recebiveis — armadilhas da carga
- **A chave única é `(stone_id, n_parcela, categoria)`**, não apenas as duas
  primeiras. A Stone emite **duas linhas com o mesmo STONE ID e número de
  parcela** quando a venda é cancelada: uma `Venda` e uma `Cancelamento`. Sem a
  categoria na chave, o `on conflict do nothing` descartava uma das duas de
  forma arbitrária (a que viesse depois no arquivo).
  Isso **tinha efeito financeiro**: `venda_diaria` desconta da venda Stone o
  `sum(abs(valor_bruto))` das linhas de cancelamento, então cancelamento
  descartado virava faturamento a mais. Corrigido em `20260780000000`; a base
  tinha 4 cancelamentos quando deveria ter 7.
- **STONE ID em notação científica** (`2,95639E+13`) é arquivo que passou pelo
  Excel: o ID tem 14 dígitos e a conversão guarda 6 significativos, perda
  irreversível. A linha nunca mais casa com a venda e vira "recebível sem venda"
  na conciliação. O importador **rejeita** essas linhas desde `20260780000000`;
  109 registros que já haviam entrado foram excluídos.
- **Dois layouts de relatório**: até 2025 a Stone exportava 18 colunas; depois
  passou a 20, com `ENTRADAS BRUTAS` e `SAÍDAS BRUTAS`. Essas duas não alimentam
  nenhuma view e estão nulas na maior parte da base, então são **opcionais** no
  importador — arquivo antigo continua válido.
- Cancelamentos anteriores ao período reimportado seguem perdidos: a linha foi
  descartada na carga original e só volta reexportando o período.

## Parâmetros administrativos

- `parametros_gerais.html` altera somente chaves já existentes de
  `public.parametros`, por `admin_salvar_parametro(text, numeric)`.
- A descrição é um título estável e não deve conter o valor atual do parâmetro.
  A migration `20260817000000` removeu os sufixos fixos “D+2” e “38%”, que
  ficavam incorretos quando o valor era alterado pela interface.
- Desde `20260815000000`, cada alteração efetiva é registrada em
  `private.parametro_historico` com valor anterior, valor novo, autor e data.
- `admin_listar_historico_parametros(integer)` entrega o histórico apenas para
  administradores. A tabela privada não possui acesso direto pelo navegador.

### Identidade da empresa

- `configuracao_empresa` mantém uma única linha com o nome e o subtítulo
  exibidos pelo painel. Somente essas duas colunas são públicas para leitura;
  não há permissão direta de escrita pelo navegador.
- `app_configuracao_empresa()` entrega a identidade antes do login, permitindo
  personalizar inclusive as mensagens de autenticação.
- `admin_obter_configuracao_empresa()` e
  `admin_salvar_configuracao_empresa(text, text)` são restritas a
  administradores. Mudanças efetivas são registradas em
  `private.configuracao_empresa_historico`.
- A migration `20260816000000` preserva a identidade atual como dado inicial.
  Em uma implantação nova, o administrador a substitui em **Parâmetros gerais**.

## Observações
- O front-end autenticado usa views `app_*` e RPCs protegidas; tabelas internas
  não são expostas para leitura anônima.
- Esse documento não altera o banco, apenas descreve o schema usado pelo app.
