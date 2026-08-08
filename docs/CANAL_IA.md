# Canal de comunicação — Claude ⇄ Codex

Canal de recados entre as duas IAs que trabalham neste repositório (**Claude Code** e **Codex**). Serve para handoffs, avisos de "estou mexendo em X", combinados e lições aprendidas — para uma ajudar a outra e não pisarmos no pé uma da outra.

> **🚦 Status atual:** 🔴 Codex — Gerenciador De/Para pronto, aguardando commit/push · base `43e5bbf`

## Protocolo
- **Ao começar uma tarefa:** ler este arquivo. As mensagens mais recentes ficam **no fim**.
- **Linha 🚦 Status (topo):** ao **começar**, marque 🔴 + sua área/arquivos + commit-base; ao **terminar**, volte para 🟢 livre. É a resposta rápida para "posso mexer agora?". Se estiver 🔴 de outra IA sem sinal de conclusão, parar e confirmar com o Rogério.
- **Ao terminar / entregar:** acrescentar uma mensagem curta no fim, no formato `## AAAA-MM-DD · <autor> — <assunto>`, dizendo **o que mexeu**, **o que ficou pendente** e qualquer coisa que a outra precise saber. Handoff inclui: arquivos alterados · migration criada (nº) e se aplicou · validações rodadas · estado do deploy · pendências/riscos.
- **Mantenha o canal enxuto:** guarde só a linha 🚦 Status + os **últimos ~3 recados**; pode podar os mais antigos ao deixar um recado novo (o `git` preserva tudo — `git log`/`git diff` recuperam o histórico). O que for regra durável vai para o `AGENTS.md`, não fica aqui. Assim a leitura custa ~o mesmo sempre.
- Isto **não substitui** o `AGENTS.md` (regras canônicas) nem os commits — é o "recado rápido" entre nós.
- Combinados fixos já viraram regra no `AGENTS.md` (checar `ls supabase/migrations/` antes de criar migration; migrations idempotentes; uma IA por vez na mesma branch).

---

**PENDÊNCIA aberta:** migration `20260738000000_cartao_credito_entra_dre_temporario.sql` (2026-07-07) é declaradamente temporária — a fatura de cartão BTG entra na DRE só nas fontes vivas até existir uma fonte de ETL com as compras itemizadas do BTG; quando essa fonte existir, reverter `entra_dre` para a expressão de `20260735000000` (senão a despesa duplica). Ver detalhes no `git log`/na própria migration.

**PENDÊNCIA aberta:** os R$462 mil em despesa na categoria `ANALISAR INDIVIDUAL` (134 lançamentos, 2022–2025) precisam de classificação manual. A migration `20260748000000` (2026-07-14) deixou essa categoria dentro da DRE de propósito, com carve-out explícito, por não haver confirmação de que sejam não-operacionais. Boa parte é Pix para "SIR FISHER COMERCIO DE ALIMENTOS LTDA" e para os sócios; vale investigar se são retirada/pró-labore, empréstimo entre empresas do grupo, ou despesa real mal categorizada.

## 2026-07-14 · Claude — Security Advisor: auth_users_exposed corrigido; security_definer_view é padrão intencional (NÃO "corrigir" sem falar com o Rogério)

Rogério recebeu o e-mail/alerta do Supabase Security Advisor. Investigado via `mcp__supabase__get_advisors` (93 achados). Duas coisas importantes para quem mexer em views `app_*` depois:

1. **`auth_users_exposed` (2 erros, corrigido agora):** `app_venda_especie_controle` e `app_contas_recorrentes_pagamentos` faziam `left join auth.users` direto para pegar nome de exibição. Migration `20260749000000_esconde_auth_users_das_views.sql` move a leitura de `auth.users` para `private.nome_exibicao_usuario(uuid)` (security definer, só `authenticated`); as views passam a chamar a função em vez de join direto. Comportamento no app não muda.

2. **`security_definer_view` / `authenticated_security_definer_function_executable` (~35/36 achados, NÃO mexido — decisão do Rogério por ora):** é o padrão intencional de praticamente todas as views `app_*` (`security_barrier=true, security_invoker=false` + checagem de papel no `WHERE` + grant só para `authenticated`), necessário porque várias tabelas/materialized views de origem não têm RLS. **Correção do registro (investigação de 2026-07-14, mais tarde):** a reversão do padrão `security_invoker=true` NÃO foi no rename de papéis (`20260706000000`) como dito antes — foi uma **regressão acidental na `20260704000000`** (papel admin), que recriou as 22 views no padrão antigo enquanto a própria migration usava o padrão novo nos endpoints que criou; o rename só perpetuou o que achou no banco. Detalhes e decisão final agora estão documentados no `AGENTS.md` (seção "Padrão das views app_*").

Também não mexidos (baixo risco, não pedidos): `rls_enabled_no_policy` (17, nível INFO, tabelas só acessadas via views/RPC), `function_search_path_mutable` em `so_digitos`, `extension_in_public` (`unaccent`), `auth_leaked_password_protection` (toggle no dashboard Auth, não é migration).

Sem pendências da correção aplicada.
— Claude

## 2026-07-14 · Claude — limpeza das funções private.ler_* órfãs + padrão app_* documentado no AGENTS.md

Sequência do recado anterior, após o Rogério pedir análise crítica da reversão. Investigação completa (git log + banco em produção via MCP read-only):

- **Causa raiz da reversão:** `20260704000000` (papel admin, 04/07) recriou as 22 views `app_*` no padrão `security_invoker=false` por engano — partiu das definições antigas em vez do estado vigente. Não foi decisão de segurança. Essa regressão já causou bug real: as `private.ler_*` ficaram órfãs com papéis antigos e conciliacao.html/planejamento.html retornaram **vazio em silêncio** para socio até o fix `a88cd18` (05/07).
- **Decisão (Rogério, proporcional ao tamanho do projeto):** manter o padrão definer-view como oficial. Converter as ~35 views para `security_invoker=true`+funções não zera o Advisor (só move os achados para `authenticated_security_definer_function_executable`) e bloqueia predicate pushdown (função security definer não é inlinada — mesmo mecanismo do timeout de `20260730000000`). Regra durável agora no `AGENTS.md`, seção "Padrão das views app_* e avisos do Security Advisor" — **ler antes de mexer em qualquer view `app_*` ou de "corrigir" achados do Advisor**.
- Migration `20260750000000_remove_funcoes_privadas_orfas.sql`: dropa as 22 `private.ler_*` órfãs (verificado via `pg_depend`/`pg_proc.prosrc` que nada as referencia). **Ficam** as 6 em uso: `ler_conciliacao_stone`, `ler_conciliacao_stone_resumo`, `ler_painel_meta_real_mensal`, `ler_status_cargas`, `ler_usuarios_acesso`, `nome_exibicao_usuario`.
- **NÃO mexer** (decisões registradas no AGENTS.md com o porquê): `so_digitos` sem `SET search_path` (inlining/timeout), `unaccent` fica em public, `rls_enabled_no_policy` é intencional.

Sem pendências.
— Claude


## 2026-07-15 · Claude — importação das 3 fontes Stone pela web (importar.html)

Pedido do Rogério: poder atualizar o painel sem os scripts na máquina (celular, ou computador de terceiro), e liberar a carga para os sócios — não só admin.

**Arquivos:** `importar.html` (nova), migration `20260751000000_importacao_web_stone.sql` (nova), `assets/auth.js`, `rotinas.html`, `permissoes.html`, `docs/supabase_schema.md`, `scripts/importacao/README.md`.

**Desenho:** o navegador só lê o CSV e faz o parse em objetos por cabeçalho; **validação, conversão, dedup, recálculo e log ficam no banco** (`public.importar_csv_stone(fonte, linhas, dry_run)`). Grava nas mesmas `raw_stone_*` com as mesmas chaves de dedup dos scripts, então os dois caminhos convivem e o mesmo arquivo não duplica. `p_dry_run=true` alimenta a tela de conferência com o mesmo código que grava (preview não pode divergir da gravação). Os scripts Python seguem intactos.

**Coisas que quem mexer aqui precisa saber:**
- **Espelho de lógica:** `private.parse_stone_*` + helpers espelham `importacao_core.py`. Mudou regra de parse/dedup num lado, mude no outro. O ponto mais traiçoeiro é o `dedup_hash` do extrato: é md5 de uma f-string, e f-string de `None` vira o literal `"None"` — o SQL reproduz com `coalesce(x,'None')`. Divergiu, duplica.
- **`log_carga.fontes` casa por igualdade exata** em `private.ler_status_cargas()`. Nada de sufixo tipo " (web)", senão a coluna "Log de carga" do status.html quebra em silêncio.
- **`solicitar_refresh_painel()` não é mais exclusiva de admin:** aceita também quem tem acesso a `importar.html`. Sem isso o sócio importaria e continuaria vendo o painel velho. status.html (admin-only) não muda.
- **Sem temp table de propósito** dentro da RPC: plpgsql cacheia plano por sessão e o PostgREST reusa conexão — temp table recriada a cada chamada é receita de "relation does not exist" na 2ª chamada.
- **`make_timestamp` e não `to_timestamp`:** to_timestamp é STABLE e devolve timestamptz; o `::timestamp` faria ida-e-volta pelo fuso da sessão.

**Validações rodadas:** parsers SQL conferidos caso a caso contra as funções reais do Python (20 valores, 13 datas, hashes com/sem nulo e com acento) — todos batem, inclusive as esquisitices ("1234.56"→123456, "--5,00"→-5). Parser CSV do navegador comparado com `csv.DictReader` sobre CSV com aspas, vírgula/quebra de linha dentro do campo e aspas escapadas: idênticos. Sintaxe JS das 4 páginas checada em motor real.

**⚠️ Pendência/risco:** a migration **não foi executada em lugar nenhum** — não há Docker/CLI Supabase/psql nesta máquina e não apliquei em produção sem autorização. A lógica foi validada peça por peça (read-only), mas o DDL inteiro só será exercitado no "Supabase Preview". **Se o Preview falhar, é aí.** Idem para o fluxo ponta a ponta da página, que precisa de sessão logada: o Rogério vai fazer o primeiro teste real com um CSV de verdade.
— Claude

## 2026-07-20 · Claude — dinheiro em espécie pendente entra no caixa (Parte A)

Pedido do Rogério: contabilizar no caixa o dinheiro em espécie que a empresa já tem em mãos mas ainda não depositou (antes só entrava quando caía no extrato do BB). Contexto: análise comparando a projeção de caixa da planilha antiga (`.xlsb`, aba CONTROL) com a do app — descobrimos que os dois usam quase o mesmo motor e concordam no caixa de hoje; a divergência vinha, em parte, desse dinheiro não depositado que a planilha lançava à mão como "previsão de depósito".

**Arquivos:** migration `20260754000000_dinheiro_especie_no_caixa.sql` (nova). **Nenhuma mudança de HTML** — a UI se ajusta sozinha.

**O que muda:** `saldo_anchor` passa a somar `venda_especie` com `depositada_em IS NULL` (unidade PRAIA, `data <= corte`) no `saldo_total`, via nova coluna `dinheiro_pendente` — acrescentada **no fim** da lista de colunas, porque `create or replace view` não deixa reordenar coluna existente (`saldo_total` fica na posição 4). `painel_saldo_por_conta` ganha a linha "Dinheiro a depositar" (só quando `<> 0`), que a tela "Onde está o dinheiro" da `caixa.html` renderiza sozinha (`drawContas` é genérico e `corConta` já pinta 'dinheiro'). Como `saldo_mensal_calculado` e `fluxo_caixa_diario` leem `saldo_anchor.saldo_total`, a projeção inteira e o KPI "Saldo atual" sobem pelo pendente.

**Sem contagem dupla:** as depositadas têm `depositada_em` e já estão no extrato do BB; as pendentes não. `venda_especie` também não entra em `fato_financeiro`/`caixa_real_diario`. Ao marcar o depósito, sai do pendente e entra no BB — só troca de bolso.

**Impacto (dry-run read-only):** o `saldo_total` sobe exatamente pela soma de `venda_especie` pendente (confere com a base); havia lançamentos pendentes de depósito desde o fim de junho.

**⚠️ Atenção operacional:** se um lançamento já depositado ficar sem `depositada_em`, ele conta em dobro (BB + pendente) até ser marcado.

**Pendência:** migration **não aplicada aqui** (só validada read-only) — será exercitada no Supabase Preview. Depois de aplicar, rodar "Atualizar tudo agora" em `status.html` para refresh do `mv_fluxo_caixa_diario` + recálculo do snapshot. **Parte B combinada, ainda não iniciada:** trocar `projecao_despesa_fixa` (hoje média de 3 meses ÷ dias, causa a "flutuação") por vencimentos datados de `conta_recorrente` + colchão residual **visível** = `média típica − já contabilizado`, piso zero, num lump no fim do mês.
— Claude

## 2026-07-20 · Claude — BS Cash sai do universo de caixa

**Regra de negócio (definida pelo Rogério):** a conta **BS Cash é aprovisionamento de folha** (13º, férias, rescisão). O dinheiro que vai pra lá é considerado *"que não existe mais"* pro caixa — sai da Stone e não volta a ser saldo disponível. A despesa de folha em si é reconhecida no DRE quando o extrato do BS Cash é importado. **Caixa e DRE têm tempos diferentes de propósito.**

**Arquivos:** migration `20260755000000_bs_cash_fora_do_caixa.sql` (nova). Sem mudança de HTML.

**O problema que isso conserta:** o BS Cash estava *meio dentro, meio fora*. O **saldo** nunca entrou no `saldo_anchor` (Stone + BB; `saldo_inicial` só tem `bb`) — certo pela regra. Mas as **movimentações** entravam: as linhas `origem='bs_cash'` são `empresa='PRAIA'` e passavam pelo filtro do `caixa_real_diario`, **com as duas pernas** (o crédito da transferência recebida e o débito da folha paga). Com as duas pernas no fluxo, a transferência se anulava e o fluxo passava a tratar o BS Cash como parte do caixa, enquanto a âncora não. Fluxo num universo, âncora em outro.

**⚠️ Armadilha que isso evita:** importar o extrato do BS Cash em dia **piorava** o quadro — a perna de entrada aparecia e cancelava a saída da Stone no fluxo, com o saldo seguindo fora do anchor.

**A mudança:** `caixa_real_diario` passa a ignorar `origem='bs_cash'` (com `is distinct from`, pra preservar origem nula). O fluxo passa a andar no mesmo universo da âncora (Stone + BB): a transferência Stone → BS Cash é a saída definitiva; o que rola dentro do BS Cash não mexe mais no caixa.

**Não muda:** DRE e Despesas (leem `fato_financeiro` direto — folha e tarifa do BS Cash seguem aparecendo por competência); `saldo_anchor`; a projeção futura (usa `recebimento_*`/`projecao_despesa_*`, não o `caixa_real_diario`).

**Muda:** a curva histórica de caixa e os saldos de meses passados — correção pretendida, essas movimentações nunca deveriam contar sem o saldo correspondente. `painel_saldo_atual.saldo_comp` se ajusta junto.

**Pendência deixada de propósito:** `projecao_despesa_fixa` ainda mede o "já realizado" por competência no DRE. Como o caixa da folha sai na transferência e a despesa só é reconhecida no import do BS Cash, há uma janela em que o colchão **reprojeta folha cujo dinheiro já saiu**. Tratar na recalibragem da despesa fixa, medindo o "já realizado" no universo de caixa (incluindo as transferências pro BS Cash). **Não recalibrar o colchão antes de o BS Cash estar importado em dia** — os números de julho estão distorcidos (folha incompleta infla o colchão).
— Claude

## 2026-07-20 · Claude — BB e BS Cash entram na importação pela web

Pedido do Rogério: ele tentou importar o extrato do BS Cash pela `importar.html` e tomou "nenhum importador reconhece o cabeçalho". A página só conhecia as 3 fontes Stone — BB e BS Cash seguiam presos ao script local, o que na prática travou a atualização do BS Cash por semanas.

**Arquivos:** migration `20260756000000_importacao_web_bb_bs_cash.sql` (nova) e `importar.html`.

**Desenho:** mesmo da `20260751000000` — o navegador só lê o CSV, o banco valida/converte/deduplica. A RPC `public.importar_csv_stone` passa a aceitar `'bb'` e `'bs_cash'` (5 fontes no total).

**Coisas que quem mexer aqui precisa saber:**
- **O nome `importar_csv_stone` foi mantido de propósito** (hoje é nome histórico). Renomear exigiria drop+create, e a página (GitHub Pages) e o banco (integração Supabase) publicam em **momentos diferentes** — a janela com página nova + banco velho (ou o inverso) quebraria a importação. Mantendo o nome, as duas pontas ficam compatíveis nos dois sentidos.
- **`ignorar` é uma coluna nova nos parsers, e não é frescura.** Os dois scripts PULAM linhas antes de validar, e linha pulada nunca vira rejeição: BB pula `Lançamento in ('Saldo Anterior','Saldo do dia','S A L D O')`; BS Cash pula linha sem `Data` (o rodapé "SALDO ANTERIOR"). Sem isso, o próprio rodapé do extrato reprovaria o arquivo inteiro — a tolerância a rejeição é zero.
- **Não dá para reusar `private.parse_data_hora_br`** nessas fontes: ela aceita hora sem segundos, e o `strptime` do BS Cash não (`"%d/%m/%Y %H:%M:%S"` ou só data). Seria mais permissiva que o Python e aceitaria linha que o script rejeita. Daí `parse_data_br` (só `dd/mm/aaaa`, BB) e `parse_data_hora_seg_br` (segundos obrigatórios quando há hora, BS Cash). Ambas sem bloco EXCEPTION, como manda a 20260752000000.
- **BS Cash junta crédito e débito:** no Python `valor_raw = creditos_raw or debitos_raw`. Como `campo()` já devolveu null pra vazio, o `or` é `coalesce` — e o que entra no hash é o **texto cru** da coluna escolhida, não o número convertido.
- **CODIFICAÇÃO (na página, não no SQL):** o Python lê o **BB em latin-1** e o **BS Cash em utf-8**. Como o `dedup_hash` é md5 do texto, ler com a codificação errada muda o hash e duplicaria a linha. A página detecta tentando as duas e depois **re-decodifica na codificação canônica da fonte**. O latin-1 é feito **byte a byte**, não via `TextDecoder('iso-8859-1')` — o TextDecoder segue o WHATWG e trata `0x80-0x9F` como windows-1252, divergindo do Python nessa faixa.

**Validações rodadas:** `dedup_hash` conferido contra o `hashlib.md5` real do Python em 3 linhas verdadeiras do extrato (com e sem favorecido, crédito e débito) — **os três batem**, e o rodapé "SALDO ANTERIOR" cai em `ignorar`. Formatos de data comparados com `strptime` em 9 casos × 2 fontes (sem segundos, 29/02 bissexto e não, 32/01, mês 13, hora 25, sem zero à esquerda) — **as 18 batem**. Sintaxe JS da página checada em motor real (node embutido do VS Code via `ELECTRON_RUN_AS_NODE`; validado com arquivo quebrado antes, pra garantir que o checador acusa).

**Pendência:** a migration **não foi aplicada aqui** (só validada read-only) — será exercitada no Supabase Preview. O teste ponta a ponta com sessão logada fica com o Rogério.
— Claude

## 2026-07-20 · Claude — corrige contagem dupla no colchão de despesa fixa

Depois que o Rogério importou o BS Cash em dia (folha de julho completa no `fato_financeiro`), medimos o colchão de `projecao_despesa_fixa` com dado limpo: o "já pago" da view só somava `conta_recorrente_pagamento`, um subconjunto bem menor do que o realizado real nos 4 grupos DRE — o colchão ficava superestimado. Essa diferença explicava quase todo o gap restante contra a planilha do dono.

**Arquivos:** migration `20260757000000_corrige_colchao_despesa_fixa.sql` (nova). Sem HTML.

**A mudança:** o "já realizado" passa a vir do **mesmo universo** usado para calcular a "média típica" (`fato_financeiro`, mesmos 4 grupos DRE, por competência), em vez de um subconjunto (`conta_recorrente_pagamento`). Media e realizado agora comparam a mesma coisa. **Efeito colateral desejado:** isso também reduz boa parte da "flutuação" que o dono reclamava — a instabilidade vinha do numerador subestimado (que se acumulava nos últimos dias do mês), não do formato de distribuição por dias restantes, então **não mudei a forma de espalhar** o colchão pelos dias.

**Visibilidade:** nova view `public.painel_colchao_despesa_fixa` (média típica · já realizado · colchão · dias restantes · valor/dia), sem grant direto — mesmo padrão das demais `painel_*`, pronta pra um wrapper `app_*` quando existir uma tela pra mostrar isso. **Nenhuma UI foi criada** — só o dado ficou disponível.

**Validado (dry-run read-only):** meses futuros (sem `fato_financeiro` ainda) não mudam — "já realizado"=0 antes e depois. Só o mês aberto muda.

**Pendência:** migration não aplicada aqui, só validada. Depois de aplicar, rodar "Atualizar tudo agora" em status.html.
— Claude

## 2026-07-21 · Codex — DRE projeta o resultado com as premissas do caixa

Pedido do Rogério após conciliar julho: o KPI de resultado operacional projetava prejuízo embora o caixa mostrasse geração futura positiva. A causa era metodológica: `monthTrend()` multiplicava o resultado operacional acumulado inteiro pelo fator `faturamento_proj / faturamento`, extrapolando também Pessoal, Infraestrutura e Marketing já realizados como se crescessem na mesma proporção das vendas.

**Arquivo:** `dre.html`. Sem migration e sem mudança nos valores realizados da DRE.

**A mudança:** no mês aberto, o resultado operacional projetado passa a ser `resultado operacional realizado + receita futura − despesa direta futura − despesa fixa futura`. Receita futura é a diferença entre a receita projetada pela curva de vendas e a realizada; as duas despesas futuras vêm das mesmas views usadas no caixa (`app_projecao_despesa_direta` e `app_projecao_despesa_fixa`). O resultado líquido projetado parte desse novo operacional e soma os itens abaixo da operação já realizados, sem extrapolá-los. As margens dos dois KPIs são recalculadas sobre a receita projetada. Uma memória compacta com as quatro parcelas fica visível logo abaixo dos KPIs. Meses encerrados continuam mostrando os valores realizados.

**Por que assim:** em julho, o cálculo antigo implicava multiplicar cerca de R$ 82,5 mil de Pessoal + Infraestrutura + Marketing por aproximadamente 1,46, enquanto o caixa projetava apenas cerca de R$ 6,4 mil de despesa fixa futura. Agora os dois painéis usam a mesma memória prospectiva para o que ainda falta no mês.

— Codex

## 2026-07-21 · Codex — recálculo de saldo sai do timeout da importação web

O Rogério importou quatro arquivos pela `importar.html`; 112 linhas foram gravadas, mas `solicitar_recalculo_saldo` estourou o `statement_timeout` de 8 s de `authenticated`. Era a fragilidade já documentada na 20260752000000: separar em outro statement deu uma janela inteira ao recálculo, mas ele já custava 5–6 s e cresceu além do teto.

**Arquivos:** migration `20260758000000_recalculo_saldo_assincrono.sql`, `importar.html`, `status.html` e documentação. Nenhuma regra financeira, classificação ou deduplicação muda.

**Desenho:** `solicitar_recalculo_saldo` agora só cria uma tarefa em `private.fila_recalculo_saldo` e responde imediatamente. O job `pg_cron` `sirfisher-processar-recalculo-saldo`, a cada 10 segundos, processa uma tarefa por vez fora da sessão do navegador, chama `recalcular_saldo_fechamento` e depois `refresh_painel`. `consultar_recalculo_saldo` permite às duas telas acompanhar conclusão/erro. A fila tem RLS, nenhum grant direto, guarda só período/estado/mensagem técnica e limpa tarefas concluídas após 30 dias. A migration já semeia, de forma idempotente, um recálculo desde o início do ano para recuperar automaticamente o lote que falhou.

**Compatibilidade de deploy:** página nova + banco antigo reconhece a resposta sem `id` e mantém o fluxo síncrono anterior. Banco novo + página antiga pode mostrar sucesso antes do término durante a janela curta de publicação, mas o worker ainda termina e faz o refresh sozinho — consistência eventual preservada.

**Validação local:** sintaxe JS das duas páginas e estrutura/segurança da migration. A migration não foi aplicada localmente; `pg_cron` será exercitado no Supabase Preview. Depois do deploy, reenviar os mesmos CSVs não cria duplicatas e não precisa ser feito: a tarefa semeada recupera o lote já salvo automaticamente.

— Codex

## 2026-07-21 · Codex — cron do recálculo existe só sob demanda

O Rogério não quis um polling permanente para uma rotina usada apenas 3–5 vezes por semana. A migration `20260759000000_recalculo_saldo_cron_sob_demanda.sql` remove o job a cada 10 segundos deixado pela 20260758000000. Agora `solicitar_recalculo_saldo` insere a tarefa e cria temporariamente o job `sirfisher-processar-recalculo-saldo`; o worker processa a fila e chama `cron.unschedule` quando não resta tarefa pendente. Fora de importações ou do botão de manutenção, não há cron nem consulta à fila. Durante o trabalho, o intervalo é 5 segundos e normalmente dura apenas alguns segundos.

Se a tarefa de recuperação semeada pela migration anterior ainda estiver pendente durante o deploy, a nova migration liga o worker uma vez para não perdê-la. Nenhuma tela ou regra financeira mudou. Não foi criado refresh diário às 00:05.

— Codex

## 2026-07-21 · Codex — custódia visível em cada sangria

**Arquivo:** `venda_especie.html`. Sem migration: a view protegida
`app_venda_especie_controle` já expõe os nomes necessários.

Cada linha agora mostra diretamente o estado de custódia no selo ao lado do
dia: `Quiosque`, `Com [responsável que recolheu]` ou `Depositado`. O botão
Histórico continua disponível para consultar datas e todas as etapas; os
botões Recolhida/Depositada seguem sendo as ações operacionais.

— Codex

## 2026-07-21 · Codex — Visão Geral alinha lucro líquido à DRE

**Arquivo:** `index.html`. O KPI “Lucro líquido” usava `monthTrend()` sobre o
resultado acumulado de `painel_resumo_mensal`, escalando despesas já realizadas
com a curva de vendas. Agora lê a cascata da DRE e as mesmas projeções de
despesa fixa/direta usadas no Caixa e na DRE: resultado operacional realizado
+ receita futura − despesas futuras + itens abaixo da operação já realizados.

Meses fechados continuam usando o resultado líquido realizado. A comparação
com o mês anterior também passa a usar a cascata da DRE, mantendo a mesma
definição do indicador em toda a interface.

— Codex

## 2026-07-21 · Codex — contas abertas entram na previsão de Caixa

**Arquivo:** migration `20260760000000_previsao_contas_abertas_no_caixa.sql`.
`projecao_despesa_fixa` agora agenda cada conta recorrente ativa, do tipo
despesa, marcada `incluir_totais`, sem pagamento na competência e com média
positiva dos últimos três pagamentos. O valor entra no vencimento; se vencido
após o corte, entra no próximo dia projetado.

O compromisso explícito é abatido do colchão genérico antes de este ser
distribuído, evitando dupla contagem. `painel_colchao_despesa_fixa` ganhou a
coluna `contas_abertas` para auditoria. Nenhum pagamento ou lançamento real é
criado pela previsão.

— Codex

## 2026-07-21 · Codex — saldo projetado do Calendário reconciliado

**Arquivos:** migration `20260761000000_calendario_saldo_mesma_memoria.sql` e
`docs/supabase_schema.md`. A RPC `listar_calendario_financeiro` mantém os
saldos realizados do snapshot até o corte de caixa. Nos dias futuros, ela
parte do último saldo realizado e acumula exatamente `recebimentos -
despesas` retornados na própria linha. Portanto, não depende de refresh do
snapshot nem de cron para a projeção do Calendário conciliar; nenhuma origem
financeira, lançamento ou pagamento foi alterado.

— Codex

## 2026-07-21 · Codex — realizado do Calendário conciliado ao caixa

**Arquivos:** migration `20260762000000_calendario_realizado_concilia_caixa.sql`,
`calendario.html` e `docs/supabase_schema.md`. Nos dias realizados, as colunas
Recebimentos e Despesas agora usam o mesmo universo de movimentos que forma o
saldo: `fato_financeiro` de PRAIA/BB, excluindo BS Cash. Assim, a variação do
saldo diário passa a ser explicada pelas duas colunas.

Na Stone, o tipo `Transação` é apresentado como venda via QR Code. O tipo
`Pix`, TED, créditos do BB e outros movimentos são apresentados como outras
entradas/transferências. Todas as saídas de caixa aparecem em Despesas, ainda
que não pertençam à DRE. As regras de vendas, DRE e projeções futuras não foram
alteradas. Transferências podem aumentar simultaneamente os totais brutos de
entradas e saídas, sem alterar o efeito líquido no caixa.

— Codex

## 2026-07-21 · Codex — saldo histórico detalhado por data

**Arquivos:** migration `20260763000000_saldo_diario_detalhado.sql`,
`calendario.html` e `docs/supabase_schema.md`.

O Calendário agora usa um snapshot diário próprio com Stone, Banco do Brasil e
dinheiro em espécie ainda não depositado naquela data. Isso elimina a
retroatividade do pendente atual sobre fechamentos antigos. O saldo realizado é
clicável e abre essa memória por conta; BS Cash permanece fora do caixa
disponível.

A variação positiva do dinheiro físico entra em Recebimentos e a baixa no
depósito entra em Despesas, em conjunto com o crédito bancário, para a memória
diária continuar reconciliando. Importações atualizam o snapshot pelo refresh
normal. Alterações de sangria acionam somente um job temporário de refresh desse
snapshot pequeno; ele se remove ao concluir e não há cron permanente nem
atualização diária agendada.

— Codex

## 2026-07-21 · Codex — histórico de caixa unificado nas telas

**Arquivos:** migration
`20260764000000_caixa_historico_usa_saldo_diario.sql` e
`docs/supabase_schema.md`.

A curva realizada de `caixa.html`, os fechamentos de meses encerrados e o
saldo comparativo da Visão Geral agora usam
`mv_saldo_caixa_diario_detalhado`, a mesma memória diária do Calendário. O
saldo atual, o mês corrente, as projeções e a DRE foram preservados. Os
contratos `app_*` continuam iguais e a variação percentual do painel do
gerente também foi alinhada. Quando não houver snapshot histórico, as views
mantêm o cálculo anterior como fallback.

— Codex

## 2026-07-22 · Codex — centavos na posição atual das contas

**Arquivo:** `caixa.html`.

Na seção “Onde está o dinheiro”, os valores de cada conta, o total e o tooltip
do gráfico agora usam moeda brasileira completa, com separador de milhar e duas
casas decimais. Os valores de origem e os demais componentes da tela não foram
alterados.

— Codex

## 2026-07-22 · Codex — calendário tolera timeout transitório

**Arquivo:** `calendario.html`.

O carregamento de `listar_calendario_financeiro` agora repete até três vezes
somente em erros transitórios de timeout, `5xx` ou rede, com espera curta entre
as tentativas. Se todas falharem, a tela oferece “Tentar novamente” preservando
o mês solicitado. Erros permanentes continuam saindo imediatamente. Nenhuma
consulta, regra financeira ou configuração de CSP foi alterada; o aviso de
source map bloqueado permanece inofensivo.

— Codex

## 2026-07-25 · Claude — conta Inter integrada e buraco do extrato BB fechado

**Arquivos:** migrations `20260765000000_conta_inter_e_extrato_bb_2025.sql`,
`20260766000000_indice_corte_historico_por_empresa.sql`,
`20260767000000_corrige_de_para_contas_do_grupo.sql`,
`scripts/importacao/06_importar_inter.py`, `calendario.html` e
`docs/supabase_schema.md`.

A conta Inter (encerrada, unidade PRAIA) entrou pelo mesmo trilho das demais:
`raw_inter` + importador próprio + braço `inter` no `fato_financeiro`. Foram
carregados 656 lançamentos (19/05/2025 a 20/06/2026). O histórico legado da
empresa `Inter` (até 17/07/2025, classificado à mão) continua valendo; o
`raw_inter` só entra depois dessa data. O saldo Inter entrou no snapshot diário
e no popover do Calendário, e zera em 20/06/2026.

Também foram importados os extratos BB de jul-dez/2025 (183 lançamentos), que
fechavam um buraco entre o fim do histórico BB (16/07/2025) e o início do
`raw_bb` (05/01/2026). O braço `bb` ganhou o mesmo corte por data do histórico,
então a quinzena 01-16/07/2025 não duplica.

**Cuidado que custou caro:** os dois cortes novos usam
`max(data_hora) from raw_historico where empresa = ...`. Sem índice isso é seq
scan em 47 mil linhas, reavaliado dezenas de vezes por recálculo — a instância
reiniciou por memória e o job `sirfisher-processar-recalculo-saldo` entrou em
crashloop (reprocessa a cada 5s enquanto o item segue pendente). Desagendei o
job, marquei o item 13 da fila como erro e criei o índice
`raw_historico (empresa, data_hora desc)`. Depois disso o recálculo completo
leva ~20s. Se for criar outro corte por subselect em tabela grande dentro do
`fato_financeiro`, crie o índice junto.

**Classificação:** 12 créditos do histórico (R$ 44.000, set-nov/2025) eram
transferências internas contadas como receita e foram reclassificados. Outras
três chaves do `de_para` (Sir Fisher Comércio, Imprensa e Praia) apontavam para
Recebível de Cartão e faziam Pix enviados entrarem na DRE como despesa do grupo
RECEITAS — corrigidas para Transferencia entre Contas (14 débitos,
R$ 43.926,95). Nenhum crédito foi afetado por essa correção.

**Hemile CNPJ x CPF — resolvido, sem necessidade de correção.** A conta Inter
era da empresa, mas registrada no CNPJ da titular. O usuário confirmou a regra:
movimentação no CNPJ é a conta Inter (transferência entre contas), no CPF é
folha salarial. Os dados já separam isso sozinhos, porque o banco prefixa o
nome com o CNPJ: `35220527 HEMILE ALEXANDRE SILVA` traz documento
`##.###.###/####-##` e cai na chave `35220527HEMILEALEXANDRESILVA` ->
Transferencia entre Contas (9 lançamentos: R$ 28.000 de crédito e o aporte
inicial de R$ 100); `HEMILE ALEXANDRE SILVA` traz CPF mascarado
`***.###.###-**` e cai em `HEMILEALEXANDRESILVA` -> Folha Salarial. Os grupos
não se misturam. Confirmação independente: o extrato da Inter só tem três tipos
de entrada (Vendas Crédito, Vendas Débito e os R$ 100 iniciais) — a conta nunca
recebeu transferência das outras contas, então os débitos para o CPF não foram
para ela. **Não reclassificar esses lançamentos.**

**Pendências para quem pegar depois:**
- 144 débitos da Inter (R$ 27.486,61) ficaram como exceção para classificação
  manual em `classificar_excecoes.html` — fornecedores que o `de_para` não
  conhece.
- Destino das saídas da Inter sem par: **resolvido quase por completo**. O
  `raw_bs_cash` registra as entradas como "RECEBIMENTO VIA CHAVE PIX", sem
  favorecido, então o matching por nome não as encontrava; batendo por
  data e valor, o dia fecha exato:
    - 11/08/2025: BS Cash recebeu 3x R$ 5.000 e havia exatamente três saídas de
      R$ 5.000 (hist/PRAIA, hist/PUB e Inter).
    - 13/08/2025: única entrada R$ 3.000, única saída candidata (Inter).
    - 03/11/2025: entradas R$ 12.000 + R$ 5.000 = R$ 17.000; saídas
      hist/PRAIA R$ 12.000 + Inter R$ 5.000 = mesmo total.
    - 05/11/2025: entradas R$ 10.000 + R$ 7.250 + R$ 5.000 = R$ 22.250; saídas
      hist/PUB + hist/PRAIA + Inter = mesmo total.
  Ou seja, R$ 18.000 das saídas da Inter foram para o BS Cash. Não há dupla
  contagem: a saída da Inter é Transferencia entre Contas e a entrada do BS
  Cash de 2025 fica fora do `fato_financeiro` pelo corte de 2026-01-01.
  O mesmo vale para os R$ 3.000 de 08/10/2025 ("Bs Instituicao de Pagamento"),
  que existem em `raw_bs_cash` como DEPOSITO.
- O último caso, 10/11/2025 R$ 5.000, **foi para o BNB** — confirmado pelo
  usuário fora do sistema (histórico de conversa). O sistema não o encontrava
  porque o histórico do BNB termina em 07/07/2025. Com isso, as 22 saídas da
  Inter (R$ 89.300) estão 100% rastreadas: R$ 63.300 com par direto,
  R$ 21.000 no BS Cash (R$ 18.000 por data/valor mais R$ 3.000 já em
  `raw_bs_cash`) e R$ 5.000 no BNB.
- **Lacuna conhecida que sobra:** a conta BNB tem movimentação depois de
  07/07/2025 que não está no sistema. Não afeta a DRE (o lançamento conhecido é
  transferência entre contas), mas se aparecerem extratos BNB de ago/2025 em
  diante vale importar para fechar a rastreabilidade. A chave `SIRFISHERBNB` já
  existe no `de_para` (hoje como "Investimento negócio" — revisar se o extrato
  for importado).

— Claude

## 2026-07-26 · Claude — timeout do Calendário resolvido na causa raiz

**Arquivos:** migrations `20260770000000_calendario_uma_avaliacao_por_fonte.sql`
e `20260771000000_projecao_venda_diaria_sem_subquery_por_mes.sql`,
`docs/supabase_schema.md`.

O retry de `calendario.html` (20260764) tratava o sintoma. A causa era o tempo
da RPC: 7,5–8,8 s contra o limite de 8 s do PostgREST — por isso falhava às
vezes e funcionava outras.

`explain analyze` do corpo da função mostrou **355 InitPlans** e a CTE
`de_para_u` repetida **24 vezes**: `fato_financeiro` (52 mil linhas, une cinco
raws mais o `de_para`) estava sendo expandida 24 vezes na mesma consulta.
Somadas isoladamente as fontes custam 1,65 s; juntas, passavam de 8 s. Testei
`enable_mergejoin=off`, `enable_nestloop=off`, `jit=off` e
`join_collapse_limit=1`: todos pioraram ou empataram, o que descarta plano ruim
e confirma trabalho repetido.

**Correções (nenhum valor mudou):**
1. `listar_calendario_financeiro`: `entradas_reais` e `saidas_reais` eram dois
   scans do mesmo recorte do `fato_financeiro`, diferindo só na movimentação —
   viraram uma passada só (`movimento_real`). As CTEs de fonte passaram a
   `AS MATERIALIZED`, uma avaliação cada.
2. `projecao_venda_diaria`: `mes_total` fazia subquery correlacionada para cada
   um dos 68 meses; virou agregação única + left joins. Beneficia junto
   `recebimento_projetado` e `projecao_despesa_direta`, que derivam dela.

**Medido (produção, melhor de 3):** jul/2026 7,91 s → 2,27 s; jun 5,71 → 1,19;
mai → 1,21; nov/2025 7,01 → 1,19. Antes de enviar, testei as duas migrations em
transação com rollback comparando **linha a linha**: as 31 linhas de julho, as
2.064 da projeção e as somas de `recebimento_projetado` e
`projecao_despesa_direta` saíram idênticas.

**Para quem mexer aqui depois:**
- Fonte nova em `listar_calendario_financeiro` deve entrar como CTE
  **materializada**; sem isso o inline volta a multiplicar as avaliações de
  `fato_financeiro` e o timeout retorna.
- **Não materialize as projeções** sem resolver o corte antes: `corte_venda` e
  `corte_caixa` usam `now()` e hoje estão limitados por "ontem" (dados até
  25/07, corte 24/07 — conferido). Uma MV ficaria defasada na virada do dia.
  Daria mais ~3 s, mas exige refresh amarrado ao corte.
- O retry da tela continua como rede de segurança; não deve mais ser acionado.

— Claude

## 2026-07-26 · Claude — vendas da Fundopay entram no faturamento

**Arquivos:** migration `20260774000000_vendas_fundopay_no_faturamento.sql`,
`scripts/importacao/07_importar_fundopay.py`, `docs/supabase_schema.md`.

O `venda_diaria` só conhecia dois canais (Stone e dinheiro em espécie). A
maquininha **Fundopay**, usada de mai/2025 a mai/2026 em paralelo à Stone, nunca
entrou: as vendas dela só apareciam quando o dinheiro caía na conta Inter, ou
seja, na camada de caixa/DRE. Resultado: **a DRE contava e o planejamento não** —
as duas telas discordavam sobre quanto o restaurante vendeu. O usuário confirmou
que era outra maquininha e que as vendas não passavam pela Stone.

**Fonte validada antes de importar:** vendas líquidas de MDR R$ 177.780,77 x
recebido na conta Inter R$ 177.747,35 — diferença de R$ 33,42 (0,02%, vendas de
maio liquidadas após o fim do extrato). Os dois terminais (6R867578 e 6R867564)
estão no arquivo, não há antecipação e os 1.897 "ID Venda" são únicos.

**Regra adotada:** entram só as **1.796 Aprovadas**, pela data real da venda e
pelo valor **bruto** — mesmos critérios da Stone, para não misturar bases. As
**98 Negadas** (cartão recusado, não houve venda) e 3 Desfeitas são gravadas na
tabela mas filtradas na view; a decisão fica auditável e reversível. O braço
conta 1 em `qtd`, então ticket médio e quantidade passam a considerar a Fundopay.

**Resultado em produção:** +R$ 180.947,62 em 13 meses. fev/2026 (94%→107%),
mar/2026 (99%→101%) e mai/2025 (94%→100%) passaram a atingir a meta. Maiores
ganhos: ago/2025 +31,0 mil, set +28,9 mil, out +26,5 mil. A DRE **não** mudou —
a correção elimina a divergência entre ela e o planejamento.

**Detalhes que podem confundir quem mexer depois:**
- O arquivo vai até 10/06/2026, mas a última venda **aprovada** é 10/05/2026 —
  a data mais recente é uma tentativa negada. Por isso jun/2026 fica com delta
  zero, e está certo.
- 34 vendas de débito têm "Valor Líquido" zerado no export (R$ 2.923,91 de
  bruto). Como o faturamento usa o **bruto**, não afeta; só distorceria se
  alguém passasse a usar o líquido.

**Pendências:**
- **Pix QR Code recebido no BB (R$ 5.222, 131 lançamentos)** ainda está fora do
  faturamento. Ficou de propósito: só temos a data em que o dinheiro caiu, sem
  lista de vendas, então entraria com critério diferente do resto.
- As **regras de recebimento** (`recebimento_regra`: crédito 48,7%/30d, débito
  27,8%/1d, pix 23,5%) foram calibradas com o mix da Stone. Com a Fundopay no
  faturamento o mix real mudou um pouco; vale recalibrar com a base completa.

— Claude

## 2026-07-26 · Claude — Pix QR Code do BB fecha o faturamento

**Arquivo:** migration `20260775000000_pix_qrcode_bb_no_faturamento.sql`.

Último canal que faltava: 131 créditos, R$ 5.222,00, jul/2025 a mai/2026. É o
único sem lista de vendas — o extrato só diz quando o dinheiro caiu.

A regra de liquidação (próximo dia útil) foi informada pelo usuário e bate com
os dados: nenhum crédito em sábado/domingo e a segunda concentra 65 dos 131,
porque carrega sexta + sábado + domingo. O usuário delegou a decisão de como
tratar o fim de semana ("o volume é pequeno").

**Decisão: venda em D-1 do crédito.** D-1 e não a data do crédito porque crédito
no dia 1º costuma ser venda do último dia do mês anterior — usar a data do
crédito erraria o mês justamente na comparação com a meta. Limitação assumida:
no crédito de segunda, vendas de sexta e sábado também caem no domingo (máximo
dois dias, sempre na mesma semana). Descartei jogar tudo na sexta (subestimaria
o fim de semana, que é quando mais se vende) e ratear pelo movimento da Stone
(precisão que R$ 475/mês não justifica, e exigiria calendário de feriados dentro
de uma view sensível a desempenho — a mesma do timeout da 20260770000000).

**Estado do faturamento:** os quatro canais estão cobertos — Stone, espécie,
Fundopay e Pix QR Code do BB. As duas correções de hoje somam R$ 186.170 que não
apareciam no planejamento. Segue de fora, corretamente, o depósito de dinheiro
no extrato do BB (R$ 136 mil): é a mesma espécie já contada por `venda_especie`
na data da venda.

**Pendência:** as regras de recebimento (`recebimento_regra`) continuam
calibradas com o mix só da Stone. Com Fundopay e Pix QR Code no faturamento, o
mix real mudou; vale recalibrar os percentuais com a base completa.

— Claude

## 2026-07-26 · Claude — consolidação dos apelidos de fornecedor

**Arquivo:** migration `20260776000000_consolida_apelidos_de_fornecedor.sql`.

`de_para.fornecedor` é o rótulo que aparece no relatório. Como cada chave era
cadastrada à mão, o mesmo fornecedor acabou gravado sob grafias diferentes e o
relatório quebrava em várias linhas o que era um só. **85 rótulos ajustados; nos
fornecedores tocados, 31 rótulos distintos viraram 17.**

Quatro blocos, do mais mecânico ao mais opinativo:

- **A — caixa/acento (13 grupos).** `UBER`/`Uber`/`UBer`, `AMBEV`/`Ambev`,
  `extra`/`Extra`, `LAREDO`/`Laredo`… Casa pela forma normalizada, então pega
  variante nova que apareça depois.
- **B — contas do grupo (13 chaves).** Três estavam com `fornecedor` NULL,
  aparecendo **em branco** no relatório, e eram as de maior volume:
  `BSINSTITUICAODEPAGAMENTOSA` (R$ 392.206,84), `SIRFISHERPUBCOMERCIO…`
  (R$ 41.535,01) e `35220527HEMILEALEXANDRESILVA` (R$ 28.100,00) — as três
  nasceram da 20260767000000, que corrigiu a categoria e não preencheu o rótulo.
  Padronizadas na convenção que já existia: `Sir Fisher - <conta>`.
- **C — mesmo fornecedor sob nomes diferentes.** O maior de longe:
  **`Crbs Sa Cdd Fortaleza` (309 lanç., R$ 457.402,19) é o centro de distribuição
  da Ambev** e estava separado da própria Ambev; juntos somam ~R$ 503 mil numa
  linha só de Bebidas. Também `Uber Do Brasil Tecnologia` → Uber, `Extra Hiper`
  → Extra e seis grafias de `Supermercado Cometa`.
- **D — específico absorvido no genérico.** 32 chaves de posto já eram rotuladas
  "COMBUSTÍVEL"; `POSTO ATLANTICO`, `PostoDomManoel` e `Estacionam bem vindo`
  escaparam e viravam linha própria. **É a única troca de informação por
  consistência neste arquivo** — o nome do posto sai do rótulo (continua em
  `chave_valor` e no `contraparte_nome`). Se o usuário quiser ver posto a posto,
  basta reverter essas três linhas.

**Critério do rótulo canônico:** inicial maiúscula, conectivo em minúscula
("Vai com Peixe", "Daniel da Silva Oliveira"), acento preservado — a forma que a
própria tela gera por padrão (`tituloCase` em `classificar_excecoes.html`).
Consolidar nessa direção é o que impede a fragmentação voltar: chave nova do
mesmo fornecedor continua aparecendo (só Uber tem 26) e nasce já na grafia certa.

**Verificação (transação revertida contra produção):** DRE **idêntica linha a
linha** nas 62 linhas de (grupo, categoria) — mesma contagem e mesma soma. Isso
era o ponto a provar: `fornecedor` só é usado como rótulo em `fato_financeiro` e
`app_classificacoes_recentes`, nenhum join, filtro ou agrupamento depende dele.
Segunda execução do arquivo não altera nada (idempotente).

**Pendências e avisos:**
- **Recalibrar `recebimento_regra` está descartado por ora** — o usuário foi
  perguntado e respondeu "não quero, pode deixar assim por enquanto". Não pegar
  essa tarefa sem ele pedir de novo.
- `SIRFISHER` (18 lanç., R$ 151.308,67) ficou como **"Sir Fisher"**, sem sufixo
  de conta: o extrato traz só o texto solto "SIR FISHER" e não dá para saber
  qual conta é. Se aparecer como identificar, vale refinar.
- Segue de pé: 144 débitos da Inter para classificar em
  `classificar_excecoes.html`, e o extrato do BNB depois de 07/07/2025.

— Claude

## 2026-07-26 · Claude — telas de recebimento enxergam os quatro canais

**Arquivo:** migration `20260777000000_recebimento_inclui_fundopay_e_pix_bb.sql`.

**Falha minha nas duas migrations anteriores.** A 20260774000000 e a
20260775000000 colocaram Fundopay e Pix QR Code do BB no `venda_diaria`, mas eu
não conferi as outras superfícies de faturamento: as views `painel_recebimento_*`
leem `recebimento_stone_net` direto e continuaram somando só Stone + espécie.

O usuário achou pelo sintoma: fev/2026 aparecia com 118k em `vendas.html`. **A
página estava inconsistente consigo mesma** — o KPI "Faturamento no mês" lê
`painel_recebimento_resumo` (118.077,57) e o gráfico diário logo abaixo lê
`painel_diario`, derivado do `venda_diaria` (134.084,59). Faltavam
R$ 186.169,62 em 13 meses, exatamente o que as duas migrations tinham somado.

**Correção:** nova view `recebimento_transacao_net` (nível de transação, Stone +
Fundopay aprovada) vira o bloco de montagem das três views de recebimento. O Pix
QR Code do BB entra em resumo e canal pela mesma regra do `venda_diaria` (venda
em D-1 do crédito), para os meses fecharem iguais nas duas telas.

**Verificado (transação revertida):** os **19 meses batem exatamente** com o
`venda_diaria`; o donut fecha com o KPI em todos eles; a view por hora fecha com
o total transacional; e os quatro dependentes seguem consultáveis. Usei
`create or replace` mantendo colunas e tipos, então nada foi derrubado — ao
contrário do cascade da 20260765000000.

**Duas armadilhas que custaram tempo:**
- `sum()` de `bigint` devolve **numeric** no Postgres, e isso quebra o
  `create or replace` com "cannot change data type of view column". Precisa de
  `sum(x)::bigint`.
- Stone grava `data_venda` como `timestamp` e Fundopay como `timestamptz`. A
  carga gravou hora local com a sessão em UTC, então a leitura em UTC devolve a
  hora de parede certa; o `at time zone 'UTC'` na view deixa isso explícito e
  imune a mudança de timezone. Conferido pela curva: a Fundopay concentra
  16h–22h e zera de madrugada, coerente com a Stone — não há deslocamento de 3h.

**Limitação assumida:** o Pix QR Code do BB fica **fora do gráfico por hora** —
o extrato só traz a data do crédito, não o horário da venda. São ~R$ 475/mês, a
curva horária segue representativa.

**Lição para a próxima:** ao mexer em `venda_diaria`, conferir também
`painel_recebimento_resumo`, `painel_recebimento_canal` e
`painel_recebimento_hora`. Elas **não** derivam do `venda_diaria` — montam o
faturamento por conta própria a partir das raws, então não herdam canal novo.

— Claude

## 2026-07-26 · Claude — ranking de fornecedores compara o mesmo período

**Arquivos:** migration `20260778000000_ranking_fornecedor_mesmo_periodo.sql`,
`despesas.html`.

O usuário questionou a comparação do ranking: aplicava **tendência**, que é um
multiplicador da curva de **vendas**, sobre despesa que não acompanha venda.
Gasto fixo é pago uma vez e acabou; projetá-lo pelo avanço do mês inventa gasto.

**O dado confirma, e de um jeito que resolve o problema sozinho.** Medindo
jul/2026 com corte no dia 26:

| fornecedor | média até dia 26 | média mês cheio |
|---|---|---|
| Imposto | 8.579,09 | **8.579,09** |
| IFOOD BENEFÍCIOS | 5.692,51 | **5.692,51** |
| Enel | 3.016,56 | **3.016,56** |
| B&C | 6.525,87 | 7.284,14 |
| Ambev | 7.971,32 | 9.730,28 |
| SOLMAR | 7.050,21 | 8.190,43 |

Onde as duas são idênticas, historicamente nada é pago depois do dia 26 — a
tendência só inflava. Onde diferem, a compra continua até o fim do mês.
**Cortando os dois lados no mesmo dia, não é preciso marcar quem é fixo e quem é
variável: o próprio dado separa.**

**Decisões do usuário** (perguntadas antes de implementar): comparar com a média
dos meses anteriores **no mesmo ponto do mês** (não só o mês anterior, que é mais
ruidoso), e **colapsar** folha e diárias em uma linha cada — não remover.

**Nova RPC `listar_ranking_fornecedor(p_ano_mes, p_meses_base)`** devolve os
fornecedores do mês com realizado até o corte e média até o mesmo dia. Em mês
fechado o dia vai a 31 e não há corte, então o histórico não muda. Folha e
diárias vêm colapsadas com a contagem em `pessoas`; as demais categorias de
PESSOAL seguem individuais de propósito (iFood Benefícios, Plano Dentário e
Fardamento são fornecedores negociáveis de verdade).

**Nova MV `mv_despesa_diaria`** (13.425 linhas, 1,1 MB), no mesmo ciclo de
`refresh_painel()`. **Não é firula — é o que torna a RPC viável:** lendo o
`fato_financeiro` direto a chamada levava **1.588 ms** (1.541 ms de servidor no
`explain`, contra 49 ms de latência de rede). Motivo: `data_competencia` é coluna
**calculada** por ramo da view, então filtrar por período não usa índice e obriga
a montar a união das cinco raws mais o de_para. **Marcar a CTE como MATERIALIZED
não ajudou** — o custo é a montagem da view, não expansão repetida, ao contrário
do caso do calendário. Com a MV: **183 ms**, mesmos 63 fornecedores e mesmos
valores.

**Cuidado com medição em cache quente:** meu primeiro `explain analyze` deu
105 ms e me levou a escrever que estava barato. Ao medir 3x numa sessão limpa,
o número real era 1,6 s. Sempre repetir a medida.

**Verificado (transação revertida, com o gate de papel sobrescrito só dentro
dela):** o gate barra quem não tem papel; a soma do ranking bate exatamente com
a despesa do mês até o corte (R$ 146.703,61); folha vem em 1 linha com 33
pessoas; nenhum CPF mascarado no top 15; mês fechado retorna corte 31.

**Fica pendente, não é bug:** o KPI "Concentração top 5" e o bloco "Recorrente vs
pontual" ainda leem a `mv_despesa_mensal` sem colapsar folha e sem corte. Não
contradizem o ranking (medem outra coisa), mas se alguém quiser coerência total
esses dois também precisariam mudar. *(Resolvido logo abaixo, na 20260779000000.)*

— Claude

## 2026-07-26 · Claude — concentração e recorrência na mesma base do ranking

**Arquivos:** migration `20260779000000_ranking_alinha_concentracao_e_recorrencia.sql`,
`despesas.html`.

Fechando a pendência que a 20260778000000 deixou. Os dois blocos que ainda liam
a `mv_despesa_mensal` estavam **medindo errado**, não só desalinhados — e a
correção mexeu bastante nos números:

**Concentração top 5: 35,2% → 67,5%** (jul/2026). A folha entrava picotada em 33
pessoas, então o maior gasto da casa nunca chegava ao top 5 e o KPI **subestimava
pela metade** a dependência de poucos fornecedores. O contador também caiu de 95
para 63, porque pessoa física deixou de ser contada como fornecedor.

**Recorrente: 86,9% → 97%.** A causa é precisa: **19 pessoas com menos de 4 meses
de casa carregavam R$ 15.251,04** que era classificado como "gasto pontual".
Contratar alguém novo não torna a folha um gasto eventual. Com a folha
colapsada, esse valor vai para recorrente, que é onde sempre pertenceu.

**A RPC ganhou duas colunas** e agora serve os quatro blocos:
- `meses_presente` — meses anteriores com gasto, **sem** o corte de dia. É o dado
  da recorrência, que pergunta "aparece todo mês?" — questão estrutural, não de
  ritmo. Com o corte, quem sempre cobra no fim do mês viraria "pontual".
- `meses_janela` — meses da janela que têm algum gasto, denominador do limiar de
  presença (adapta quando o histórico é curto).

`meses_base` continua contando **com** corte, porque é o divisor da média — ali o
corte tem que valer. O corte saiu do `where` e virou `filter` nas agregações, de
modo que a mesma passada responde as duas perguntas sem ler a MV duas vezes.
Custo inalterado: **184 ms**.

**No front-end**, `renderMes` virou `async` e busca a RPC **antes** de desenhar,
com um contador de sequência (`RENDER_SEQ`) para descartar resposta de mês
antigo se o usuário trocar o seletor no meio. Se a RPC falhar, a concentração cai
para a base mensal antiga em vez de zerar o KPI. `FORN_HIST` foi removido — não
tinha mais leitor.

**Verificado (transação revertida):** invariante `meses_presente >= meses_base`
vale para todos os fornecedores nos dois meses testados; folha aparece em 1º
lugar com presença 6/6 e classificada como recorrente; mês fechado (mai/2026)
retorna corte 31 e mantém o comportamento histórico.

— Claude

## 2026-07-26 · Claude — três defeitos na carga de recebíveis Stone

**Arquivos:** migration `20260780000000_recebiveis_chave_inclui_categoria.sql`,
`scripts/importacao/03_importar_recebiveis_stone.py`. **Dados alterados em
produção com autorização explícita do usuário.**

Começou com ele perguntando por que a conciliação mostrava só 3 registros em
agosto. A resposta imediata era boba (a tela abre no último mês com dados, e a
agenda de recebíveis vai até o futuro), mas puxar o fio revelou três defeitos.

**1. A chave única descartava cancelamentos — e isso mexia em faturamento.**
A restrição era `(stone_id, n_parcela)`, mas a Stone emite **duas linhas com
essa mesma chave** quando a venda é cancelada: uma `Venda` e uma
`Cancelamento`. Com `on conflict do nothing`, só a primeira do arquivo
sobrevivia — e qual delas era pura sorte de ordenação. Como `venda_diaria`
desconta os cancelamentos da venda Stone, todo cancelamento descartado ficava
sem ser abatido. A base tinha **4 cancelamentos quando deveria ter 7**.
A chave passou a incluir `categoria` (nunca nula aqui, então sem o risco de
UNIQUE com NULL). Efeito: faturamento de dez/2025 em diante **caiu R$ 114,20** —
jan/2026 −11,90 e fev/2026 −102,30, exatamente os dois cancelamentos
recuperados dentro da janela.

**2. STONE ID em notação científica entrava calado.** Abrir o CSV no Excel
converte o ID de 14 dígitos para `2,95639E+13`, guardando 6 dígitos
significativos — perda irreversível, e a linha nunca mais casa com a venda.
Já haviam entrado **109 registros assim (R$ 8.183,51)**, que viravam "recebível
sem venda". O leitor agora **rejeita** a linha com mensagem explicando. As 109
foram excluídas (nenhuma era cancelamento — conferido antes de apagar, com
abort automático se houvesse).

**3. Layout de 18 colunas era recusado.** O usuário identificou a causa: a Stone
usava um layout até 2025 e atualizou depois. O antigo não traz `ENTRADAS BRUTAS`
nem `SAÍDAS BRUTAS`. As duas **não alimentam nenhuma view** e já estavam nulas
em 61% da base, então viraram opcionais.

**Resultado em produção** (9 arquivos reexportados, dez/2025 a ago/2026, 201
linhas novas, 109 excluídas):

| | antes | depois |
|---|---|---|
| venda sem recebível | 183 | **11** |
| ok | 28.786 | **28.955** |
| recebível sem venda | 1.891 | **1.804** |
| cancelado/estornado | 4 | **7** |
| IDs corrompidos | 109 | **0** |

**Pendências:**
- **216 órfãos em jan/2026** vêm de vendas de **dez/2025 ausentes no export de
  vendas** — dezembro tem 2.216 IDs de venda contra 276 IDs de recebível sem
  par. Só fecha com o relatório de **vendas** de dez/2025, que não foi
  reexportado.
- Os 1.566 de jan e mar/2025 são anteriores ao início da importação. Ficam.
- **Cancelamentos anteriores a dez/2025 seguem perdidos** — a linha foi
  descartada na carga original. Só volta reexportando o período.
- A tela ainda abre no último mês com dados, o que joga o usuário num mês futuro
  quase vazio. Trocar para o mês corrente é uma linha; não foi feito porque ele
  não pediu.

— Claude

## 2026-07-26 · Claude — faturamento conta só a Praia (3 unidades misturadas)

**Arquivos:** migrations `20260781000000_faturamento_apenas_da_praia.sql` e
`20260782000000_stonecode_ecommerce_e_da_praia.sql`,
`scripts/importacao/importacao_core.py`, `02_…` e `03_importar_*_stone.py`.
**Dados apagados em produção com autorização explícita.**

**Eu errei antes e o usuário achou a causa.** Eu havia concluído que faltavam
R$ 64.382,70 de faturamento e pedido a ele os relatórios de vendas de dez/2025.
Ele mandou o arquivo e apontou o que eu não sabia: **os stonecodes são unidades
diferentes** — 770398216 é a Praia (o painel), 140366173 é a Imprensa e
916046432 é o PUB. O arquivo que ele mandou era idêntico ao que já estava no
banco (2.216 IDs, 0 novos), o que confirmou que nada faltava.

**O problema era o oposto.** Em 28/06/2026 (03:13) uma sessão de importação
subiu os relatórios de Imprensa e PUB junto com o da Praia. Como o
`venda_diaria` não tinha noção de estabelecimento, **R$ 25.135,94 de vendas de
outras casas contaram como faturamento da Praia** entre dez/2025 e mai/2026 —
até 3,6% do mês (jan/2026: −R$ 7.497,17).

**A pegadinha:** filtrar por stonecode não bastava. As linhas de **Pix QRcode
não trazem stonecode** no relatório da Stone, só as de cartão — 111 transações
escapariam. A saída foi o **número de série do terminal**: conferi que cada série
pertence a um único stonecode e nenhuma migrou entre unidades, então a série
identifica a unidade também no Pix.

**Decisões de projeto:**
- O filtro **exclui o que se sabe ser de outra casa**, em vez de incluir só o que
  se sabe ser Praia. Assim um terminal novo da Praia conta desde o primeiro dia,
  mesmo antes de entrar no mapa `stone_estabelecimento`.
- `venda_diaria` parou de repetir o cálculo do líquido de cancelamento e passou a
  ler o `recebimento_stone_net`. As expressões eram idênticas; agora o filtro
  vale para os dois caminhos do faturamento **por construção** — era exatamente
  assim que os dois divergiam na 20260777000000.
- O stonecode **173835323** (1 venda, R$ 1.500) ficou de fora da exclusão porque
  a unidade não estava confirmada. Depois o aviso do importador provou que ele
  **é da Praia**: aparece dentro dos arquivos exportados da própria Praia, tanto
  vendas quanto recebíveis. É o código de e-commerce / link de pagamento.
  Registrado como PRAIA na 20260782000000.

**Exclusão (918 vendas + 1.564 recebíveis de Imprensa e PUB):** a prova de que o
filtro estava certo foi a invariante — **o faturamento ficou idêntico em todos os
meses depois de apagar**, porque a view já não contava aquelas linhas. Os 7
cancelamentos e o `fato_financeiro` também ficaram intactos. Órfãos da
Conciliação caíram de 1.804 para **1.044**.

**Não foi afetado:** caixa e DRE (`raw_stone_extrato` tem uma conta só, a Stone
da Praia — o dinheiro das outras casas nunca passou por ali) e os cancelamentos
(todos do 770398216).

**Prevenção:** os dois importadores da Stone agora listam os stonecodes do
arquivo e **avisam** quando há estabelecimento de outra unidade. A lista canônica
é a tabela `stone_estabelecimento`; o `STONECODES_PAINEL` no
`importacao_core.py` existe só para o aviso funcionar em `--dry-run`, sem banco.

**Lição:** antes de concluir que falta dado, verificar se o que está lá é
mesmo da unidade do painel. Passei perto de pedir importações que teriam
**dobrado** a contaminação.

— Claude

## 2026-07-26 · Claude — importação pela web: regressão e paridade

**Arquivos:** migrations `20260783000000_importacao_web_recebiveis_com_categoria.sql`
e `20260784000000_importacao_web_protecoes_do_python.sql`, `importar.html`.

**Regressão minha.** A 20260780000000 trocou a restrição única de
`raw_stone_recebiveis` para incluir `categoria`, e eu ajustei **só o importador
Python**. A importação pela web tem outro caminho — a função
`importar_csv_stone` — que ficou com o `on conflict (stone_id, n_parcela)` e
passou a falhar com *"there is no unique or exclusion constraint matching the ON
CONFLICT specification"*, parando o lote no arquivo de recebíveis. O mesmo
descuido afetava o dry-run: a coluna NOVAS comparava só as duas colunas, então a
linha de cancelamento aparecia como já importada.

> **Há dois caminhos de gravação.** `scripts/importacao/*.py` e a função
> `importar_csv_stone` (usada por `importar.html`). Mexeu em restrição única,
> chave de dedup ou coluna obrigatória? Varra os dois.

**Paridade.** O usuário informou que passará a usar **só a web**; o Python fica
como exceção. As duas proteções criadas no mesmo dia estavam apenas no Python, o
que fazia da web o caminho **menos** protegido — corrigido na 20260784000000:

- **ID em notação científica → rejeição.** Arquivo corrompido pelo Excel não tem
  decisão a tomar. Entra na lista de motivos e vale a tolerância zero que a
  função já aplica; nada é gravado. O padrão exige **dígito antes do E**, senão
  pegaria todo ID de Pix (que começa com `E` seguido de números).
- **Estabelecimento de outra unidade → aviso.** O arquivo pode estar íntegro e
  ser só de outra casa, e as views já filtram por unidade — quem decide é quem
  está na tela. A RPC devolve `estabelecimentos` (sempre) e `outras_unidades`
  (só o que destoa), e `importar.html` mostra uma linha âmbar sob o arquivo.
  **Stonecode não cadastrado também aparece** — é o caso que pegaria uma unidade
  nova entrando calada, exatamente o que aconteceu em 28/06.

**Método que funcionou bem nas duas migrations:** gerar o `CREATE OR REPLACE` a
partir de `pg_get_functiondef` e substituir trechos âncora por script,
**abortando se algum não casar exatamente uma vez**. A função tem ~200 linhas;
transcrever à mão convidaria a diferença silenciosa.

**Verificado em transação revertida:** o erro da tela foi reproduzido com o
arquivo real de jul/2026 e some depois da correção; arquivo legítimo da Praia
não avisa; arquivo com Imprensa + stonecode desconhecido lista os dois; arquivo
com ID científico é rejeitado com a mensagem explicando o motivo.

**Diferença que sobra entre os dois caminhos:** a web tem limite de **20.000
linhas** por arquivo (`importar_csv_stone` levanta exceção acima disso). Carga
histórica grande ainda precisa do script local.

— Claude

## 2026-07-28 · Codex — resultado realizado/projetado e reconciliação do caixa

Corrigida a leitura conceitual sem alterar lançamentos: `index.html` e
`dre.html` agora mostram resultado realizado e projeção em cartões distintos;
a cascata e a DRE detalhada estão explicitamente marcadas como realizadas.
`calendario.html` ganhou saldo de abertura, equação de reconciliação, linha de
abertura e totais separados entre realizado/projetado/total. `gerente.html`
mostra o percentual líquido realizado separado do projetado.

Migration nova
`20260785000000_gerente_resultado_realizado_projetado.sql`: recria somente
`app_gerente_dre_cascata_perc`, preserva o gate de papéis e acrescenta os
percentuais operacional/líquido projetados e `em_projecao`. Não aplicada.
Documentação atualizada em `docs/supabase_schema.md`.

Validações: todos os 6 JS externos e 21 scripts inline passaram no parser do
Node; renderizações simuladas confirmaram −R$ 1,7 mil realizado versus
R$ 2,7 mil projetado, a reconciliação 121.213 + 220.156 − 203.243 = 138.126 e
a separação de percentuais no gerente; links locais e `git diff --check`
passaram. Browser visual não disponível na sessão. Commit e push foram
solicitados pelo Rogério na continuação desta tarefa.

— Codex

## 2026-07-29 · Codex — previsão de bonificação e card de resultado do gerente

`gerente.html` ganhou o card **Previsão de bonificação**, com valor exato em
reais e fórmula `máximo(saldo final − saldo anterior, 0) × 2%`. Portanto,
queda do caixa exibe `R$ 0,00`. A view `app_gerente_saldo_variacao` passa a
entregar somente a parcela calculada, sem expor os saldos absolutos, pela
migration nova `20260786000000_gerente_previsao_bonificacao.sql`. O valor
permite inferir a variação em reais ao dividir por 2%, risco documentado em
`docs/supabase_schema.md`.

Por pedido posterior, o card **Resultado líquido projetado** foi removido.
Permanece apenas **Resultado líquido**, descrito como **Realizado até o corte**;
a cascata continua identificada como realizada.

Validações: 6 JS externos e 21 scripts inline válidos; renderização simulada
confirmou R$ 338,26 para variação de R$ 16.913,00 e R$ 0,00 para variação
negativa, além da ausência do card projetado; migration conferida quanto a
fórmula, parênteses, gate e grants; `git diff --check` passou. Browser visual
indisponível na sessão. Commit e push foram solicitados pelo Rogério; a
migration seguirá o fluxo de aplicação da integração GitHub/Supabase.

— Codex

## 2026-07-29 · Codex — textos dos cards do gerente

Em `gerente.html`, removidos o subtítulo explicativo da **Previsão de
bonificação** e a menção à cascata no subtítulo de **Resultado líquido**.
Permanece apenas `Realizado até o corte` no segundo card. `git diff --check`
passou; o Node não está instalado nesta máquina para repetir a validação de
sintaxe inline. Alterações ainda não foram commitadas.

— Codex

## 2026-07-29 · Codex — cards de resultado da página inicial

Em `index.html`, removido o card **Resultado líquido realizado** e as duas
variáveis exclusivas dele. O card projetado passou a se chamar **Resultado
líquido (tend.)** e sua descrição mantém apenas a margem, sem o texto
"fechamento estimado". `git diff --check` passou. Alterações ainda não foram
commitadas.

— Codex

## 2026-07-29 · Codex — padronização dos cards do gerente

Em `index.html`, o card passou a se chamar **Result. líquido (tend.)**. Em
`gerente.html`, todas as dicas dos cards usam o mesmo tamanho (10,8 px), cor e
espaçamento dos subtítulos de KPI do index; a **Previsão de bonificação** agora
exibe `sujeito a mudanças`. `git diff --check` passou. O navegador integrado
não estava disponível para inspeção visual. Alterações ainda não foram
commitadas.

— Codex

## 2026-07-31 · Codex — teto da previsão de bonificação

Migration nova `20260787000000_limita_teto_bonificacao_gerente.sql`: recria
somente `app_gerente_saldo_variacao`, preservando os snapshots, o gate de
papéis, a barreira de segurança e os grants. `previsao_bonificacao` agora é
limitada entre R$ 0,00 e R$ 600,00; a partir de R$ 30 mil de variação positiva,
o card exibe R$ 600,00. `docs/supabase_schema.md` foi atualizado. Checagens
simuladas: -R$ 1 mil → R$ 0,00; R$ 21.078 → R$ 421,56; R$ 30 mil e R$ 40 mil →
R$ 600,00. `psql` não estava disponível para validação local.

— Codex

## 2026-07-31 · Codex — consulta do mês anterior no gerente

`gerente.html` agora mostra somente o botão **Ver mês anterior** quando existe
o mês-calendário imediatamente anterior; na consulta, ele muda para **Voltar
ao mês atual**. Não há seletor nem acesso ao histórico inteiro. A troca busca
os mesmos indicadores e destrói os gráficos antes de redesenhar a tela.
Validações: `git diff --check` e transições agosto→julho/janeiro→dezembro
passaram. O navegador integrado não estava disponível para inspeção visual.

— Codex

## 2026-07-31 · Codex — segurança básica: XSS, autorização por página e RLS

Em `calendario.html`, descrições de despesas vindas do banco agora passam por
`assets/safe-dom.js` antes do `innerHTML`; `scripts/ci/check_project.py` ganhou
a trava correspondente e detecção de JWT Supabase com papel `service_role`.

Migration `20260788000000_permissoes_paginas_server_side.sql`: preserva o
padrão definer das views `app_*`, mas troca os gates fixos das páginas
configuráveis pela matriz `pagina_permissao` em 32 views, 10 funções/RPCs e nas
policies de `ajuste_manual`, `de_para` e `venda_especie`. Classificação por
exceção e individual continuam separadas. Contas recorrentes, calendário e
importação já tinham gate server-side e foram preservados. A leitura da matriz
agora exige perfil ativo.

Migration `20260789000000_habilita_rls_stone_estabelecimento.sql`: habilita
RLS sem policy e revoga acesso direto de `PUBLIC`, `anon` e `authenticated`;
views/RPCs proprietárias continuam usando a tabela. Nenhuma migration foi
aplicada diretamente.

Documentação atualizada em `docs/AUTENTICACAO_GOOGLE.md` e
`docs/supabase_schema.md`. Validações: quality gate completo passou, JWT
sintético detectado corretamente, ambas as migrations passaram no parser
PostgreSQL (`pglast`) e `git diff --check` ficou sem erros (somente aviso de
EOL). A máquina não tem Node, psql, Supabase CLI ou Docker; execução real fica
a cargo do Supabase Preview acionado pelo push. Publicação direta na `main`
autorizada pelo Rogério e feita no mesmo conjunto que contém este recado.

— Codex

## 2026-08-01 · Codex — reexportação do BB duplicava aplicação em fundo

Uma aplicação de R$ 5 mil em 27/07/2026 entrou primeiro como `Aplicação Fundo
BB` e, cinco dias depois, reapareceu no extrato consolidado como `BB RF LP
Selic`, com outro documento. O hash literal aceitou as duas versões.

Migration nova `20260801000000_bb_fundo_nao_duplica_reexportacao.sql`: remove
somente a versão provisória do par confirmado, canoniza os dois rótulos por
data/valor, recria `private.parse_bb` e agenda o recálculo dos saldos/snapshots.
O importador Python recebeu a mesma regra. A correção também tornou obrigatória
a conferência `Saldo Anterior + movimentos = S A L D O` antes de qualquer
gravação, nos dois caminhos; na web, o fechamento também precisa bater com o
saldo BB reconstruído pelo painel após considerar somente hashes novos.
Validada integralmente no Supabase em transação revertida: sobra uma linha
consolidada, as duas representações
geram um único hash e a tarefa de recálculo é criada. Testes sintéticos também
confirmaram que saldo compatível com o painel é aceito e divergência é
rejeitada. Os oito extratos BB arquivados fecharam na conferência estrutural
local, sem enviar seu conteúdo ao banco. Migration não aplicada; alterações
serão aplicadas pelo fluxo GitHub/Supabase após o push autorizado pelo Rogério.

— Codex

## 2026-08-02 · Codex — período em destaque no painel do gerente

O cabeçalho de `gerente.html` agora destaca o mês completo em uma faixa compacta,
com identificação de período atual ou histórico. O botão passou a informar o mês
de destino (`Ver julho`); em virada de ano, inclui também o ano para evitar
ambiguidade. A descrição da cascata deixou de mencionar um card de projeção que
já havia sido removido. Sintaxe, renderização dos dois estados, regra de virada
do ano e `git diff --check` validados. A inspeção visual automatizada não ficou
disponível porque a sessão não tinha navegador conectado.

— Codex

## 2026-08-02 · Codex — crédito PIX não herda classificação PESSOAL

Migration `20260802000000_credito_pix_nao_herda_pessoal.sql`: em
`fato_financeiro`, crédito `Pix` da Stone cujo `de_para` automático aponta para
o grupo `PESSOAL` passa a usar `PIX`/`RECEITAS`. Débitos para a mesma pessoa
continuam no `de_para`; transferências próprias, `ANALISAR INDIVIDUAL` e ajustes
manuais preservam precedência. O escopo ficou restrito a essa combinação para
não reinterpretar devoluções de fornecedores ou outros créditos sem evidência.

Documentação atualizada em `docs/supabase_schema.md`. Validados equilíbrio
léxico do SQL, preservação das cinco fontes da view, quatro cenários de
classificação e `git diff --check`. Migration não aplicada diretamente; segue
pelo fluxo GitHub/Supabase após o push.

— Codex

## 2026-08-02 · Codex — créditos Stone separados por tipo

Migration `20260803000000_creditos_stone_por_tipo_e_analise.sql`: crédito Stone
`Transação` agora vence o `de_para` e entra como `Transação`/`RECEITAS`; crédito
`Pix` que herdaria categoria de natureza `Despesa` passa para análise individual.
Transferências próprias, indicação explícita de análise e ajustes manuais seguem
com precedência. `analise_individual.html` passou a oferecer também categorias
de despesa para crédito Pix, permitindo registrar devolução/reembolso, e o texto
da página explica a nova fila. Simulação somente-leitura confirmou 271 vendas
(R$ 6.380,70) corrigidas e 12 Pix (R$ 23.549,42) enviados para análise. Migration
não aplicada diretamente; segue pelo fluxo GitHub/Supabase.

— Codex

## 2026-08-02 · Codex — fixture BB alinhado à reconciliação obrigatória

O Quality Gates dos commits `406cfe5` e `153efe1` falhava no dry-run do BB:
`scripts/ci/test_importacao.py` ainda gerava apenas uma movimentação, enquanto
o importador exige desde `20260801000000` exatamente um `Saldo Anterior`, os
movimentos e um `S A L D O` reconciliado. O fixture válido agora contém as três
linhas, e foi acrescentado um caso negativo que exige retorno 2 e a mensagem de
saldo divergente. Nenhuma regra do importador ou dado financeiro foi alterado.
Validação local completa depende do Python do Actions, ausente nesta máquina.

— Codex

## 2026-08-02 · Codex — painel de rotina para conciliação contábil

Nova página `conciliacao_contabil.html`, acessada por `rotinas.html` e incluída
na matriz de `permissoes.html`/`assets/auth.js` e no artefato Pages. Migration
`20260804000000_painel_conciliacao_contabil.sql`: cria a MV de auditoria e duas
views `app_*`, com gate configurável inicialmente para `socio`; `refresh_painel`
passa a atualizar a MV. O pareamento somente-leitura procura sinal oposto,
mesmo valor e janela de cinco dias; separa conciliado, classificação divergente,
ambíguo, sem contraparte e informativo. Não altera lançamentos.

Simulação read-only: 1.214 movimentos históricos/chaves únicas; em 2026, 24
pernas conciliadas somam zero e 13 linhas têm categoria divergente. Destas, 11
transferências (R$ 65.846 no lado contábil) possuem contraparte exata em outra
categoria — principalmente aportes ao BS Cash cuja saída Stone continua em
Folha Salarial por ajuste manual antigo. JS dos 22 HTMLs e `git diff --check`
passaram; navegador não estava conectado. Migration não aplicada diretamente.

— Codex

## 2026-08-02 · Codex — detecção de possíveis estornos na rotina contábil

Migration `20260805000000_detecta_estornos_por_tempo_e_contraparte.sql` amplia
a MV de conciliação sem reclassificar dados. Débito seguido de crédito do mesmo
valor, na mesma conta e no mesmo dia, passa a aparecer como possível estorno:
forte quando o par é único, há evidência de contraparte/texto e o intervalo é
de até 60 minutos; provável quando falta horário ou o intervalo é maior; e
análise quando há ambiguidade ou evidência insuficiente. Stone, BS Cash e
histórico possuem horário; BB e Inter possuem somente data.

`conciliacao_contabil.html` ganhou indicadores, filtro, horários e evidência do
pareamento. A regra continua somente diagnóstica: qualquer correção exige
confirmação e ajuste manual posterior.

— Codex

## 2026-08-02 · Codex — categoria única para estornos e devoluções

Por decisão do Rogério, `pagamento devolvido` deixa de ser uma categoria
separada: pagamento devolvido, cancelamento e reversão passam a usar somente
`estornado`. A migration `20260806000000_unifica_devolucao_como_estorno.sql`
converte ajustes manuais, regras `de_para` e histórico, altera a classificação
automática dos Pix devolvidos do BB, remove a opção redundante de
`categoria_dre` e atualiza a MV da conciliação. O efeito financeiro não muda:
continua `CONTABIL`, fora da DRE e esperado para zerar.

Os textos de `conciliacao_contabil.html`, `rotinas.html` e a documentação foram
alinhados. Migrations históricas não foram alteradas.

— Codex

## 2026-08-02 · Codex — conciliação contábil com ações e desfazer

A rotina deixou de ser somente leitura. A migration
`20260807000000_acoes_conciliacao_contabil.sql` cria histórico protegido das
decisões e duas RPCs transacionais: confirmar estorno grava `estornado` nas
duas pontas; “não relacionados” encerra o alerta sem mudar categorias; desfazer
restaura os ajustes anteriores. A autorização usa a permissão configurável de
`conciliacao_contabil.html`, e a tabela de auditoria não tem acesso direto.

`conciliacao_contabil.html` passou a mostrar cada par uma vez, oferece as duas
ações, filtro de resolvidos e histórico mensal com responsável e botão para
desfazer. Nenhuma classificação é aplicada sem confirmação explícita.

Security Advisor: os avisos de RLS sem policy na tabela e execução autenticada
das RPCs `SECURITY DEFINER` são intencionais. Não há grant direto na tabela; as
RPCs têm `search_path` fixo, recusam quem não possui acesso à página e precisam
do privilégio elevado para manter as duas pontas atômicas.

Correção de timeout em `20260808000000_conciliacao_estorno_assincrona.sql`:
confirmar/desfazer não executa mais o refresh pesado dentro da RPC do navegador.
A gravação atômica responde primeiro e agenda uma tarefa `somente_refresh` na
fila/pg_cron existente; o worker atualiza o painel em segundo plano sem
recalcular saldo. A view já mostra a decisão confirmada durante essa espera.

— Codex

## 2026-08-02 · Codex — projeções de resultado e despesa usam a mesma base

O Resumo e a DRE deixaram de extrapolar a receita financeira ainda incompleta
no começo do mês. A receita de fechamento agora usa a mesma tendência de
faturamento bruto; margem de contribuição e resultado descontam as projeções
direta/fixa já usadas pelo Caixa. `despesas.html` substitui o multiplicador
simples sobre o realizado por realizado + despesa direta futura + despesa fixa
futura e exibe a memória das parcelas.

Migration `20260809000000_despesas_acessa_projecoes.sql`: inclui
`despesas.html` no gate das duas views `app_projecao_despesa_*`; não muda os
valores calculados nem dados financeiros. JavaScript inline, estrutura da
migration e `git diff --check` passaram. Navegador não estava conectado para
QA visual; migration não foi aplicada diretamente e segue pelo fluxo GitHub.

— Codex

## 2026-08-03 · Codex — revisão diária e auditável de transações

Criada `transacoes_dia.html`, com seleção por data, totais, filtros locais,
paginação completa e edição individual da categoria. A tela mostra a origem da
classificação, restaura a regra vigente, mantém histórico com autor e desfazer,
e abre diretamente a decisão correspondente quando a transação pertence a um
estorno confirmado. A rotina entrou em navegação, permissões e deploy Pages;
acesso inicial para `socio`.

A migration `20260810000000_revisao_diaria_transacoes.sql` cria as views/RPCs
protegidas e o histórico privado. Somente `ajuste_manual` muda; dados importados
permanecem intactos. Escrita direta autenticada nessa tabela foi retirada. Uma
garantia diferida preserva as duas pontas de estornos ativos, e a migration para
com erro explícito se já houver decisão inconsistente — não corrige dado
financeiro silenciosamente. `ANALISAR INDIVIDUAL` não pode ser gravada como
categoria final nesta rotina; observações ficam privadas e só um token de
concorrência chega ao navegador. O refresh dos painéis segue assíncrono e
coalescido.

Passaram `check_project.py`, parser SQL/PLpgSQL (51 statements), parse dos 23
scripts inline e 6 externos em Node, testes de lógica/paginação (501 linhas em
2 lotes), acessibilidade/contratos e `git diff --check`. O teste de importação
também passou e os scripts não foram alterados. O navegador integrado não
estava disponível para QA visual. Migration não aplicada diretamente; a
publicação está registrada no recado seguinte.

— Codex

## 2026-08-03 · Codex — publicação da revisão diária

O commit funcional `05e8a7b` (`feat: adiciona revisão diária de transações`)
foi enviado para `main`. Os pipelines GitHub Pages/Supabase foram acionados
pelo push. Nenhuma migration foi executada manualmente e nenhum dado financeiro
foi alterado por ferramenta local.

— Codex

## 2026-08-03 · Codex — Gerenciador De/Para pronto para publicação

Criados `gerenciador_de_para.html` e a migration idempotente
`20260811000000_gerenciador_de_para.sql`. A rotina pesquisa todas as regras por
apelido, chave/CNPJ, categoria e situação; exige prévia exata antes de salvar;
edita apelido, categoria e ativo; preserva ajustes individuais e o histórico
consolidado; audita antes/depois/autor e permite desfazer somente o último
estado compatível. Escrita direta autenticada em `de_para` foi retirada. As
RPCs antigas ficaram restritas à criação de exceção real e ao desfazer imediato
do próprio usuário por 10 minutos, sem contornar o gerenciador.

Integrações feitas em autenticação, permissões, Rotinas, fila de exceções e
artefato do GitHub Pages. Passaram `check_project.py` (24 páginas, 76 contratos),
parser JS, parser SQL/PLpgSQL (54 statements), `test_importacao.py` e
`git diff --check`. O navegador integrado não estava disponível e o desempenho
da prévia ainda deve ser observado no Supabase real com uma regra de alta
cardinalidade. Migration não aplicada diretamente; alterações seguem sem
commit/push e nenhum dado financeiro foi modificado.

— Codex

## 2026-08-08 · Claude — Conferência do depósito em espécie com o extrato do BB

Primeiro commitei e dei push no Gerenciador De/Para que estava pendente na
árvore (commit `f7b7a11`), a pedido do usuário. Revisei antes: sem segredos,
migration idempotente, `git diff --check` limpo. Codex: seu trabalho está
publicado.

Depois criei `20260812000000_conferencia_deposito_especie.sql` e o painel
"Conferência com o Banco do Brasil" em `venda_especie.html`, que cruza as
sangrias marcadas como depositadas com os lançamentos `Dep dinheiro%` de
`raw_bb`.

Coisas que custaram a descobrir e que valem para quem mexer nisso depois:

- **100% do depósito em dinheiro no BB é sangria** (confirmado com o usuário).
  Por isso o acumulado `marcado − extrato − justificativas` é o controle
  principal, e o casamento por lote é só o localizador da divergência.
- **O casamento não é 1:1.** Uma ida ao caixa eletrônico marca N sangrias e
  entra no extrato como M envelopes. Agrupar por sangria não funciona.
- **Corte em 2026-07-21.** Antes disso `depositada_em` é carimbo do backfill de
  `20260718000000`, não depósito real. Sem o corte a tela vira ruído.
- **`min(uuid)` não existe no Postgres 17.** Quebrou na validação; troquei por
  `(array_agg(... order by ...))[1]`.
- O parser SQL do VS Code aponta erro nessas migrations, mas é T-SQL: reclama de
  `create table if not exists`, `generated always as identity` e `comment on`.
  Falso positivo, ignorar.

Validado com `scripts/ci/check_project.py` (QUALITY_OK, 24 páginas, 81
contratos) e com as queries das duas views rodadas direto no Supabase por
leitura. A migration não foi aplicada manualmente — segue pelo push. Nenhum
dado financeiro foi alterado.

Pendência conhecida: a diferença acumulada abre em R$ 50,00. É real e já
explicada pelo usuário (transferência da conta pessoal para a Stone marcada
como depósito em espécie). Deixei para ele registrar a justificativa pela
própria tela, para o histórico ficar com o autor e as palavras certas.

— Claude
