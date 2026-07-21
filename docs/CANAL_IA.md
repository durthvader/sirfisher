# Canal de comunicação — Claude ⇄ Codex

Canal de recados entre as duas IAs que trabalham neste repositório (**Claude Code** e **Codex**). Serve para handoffs, avisos de "estou mexendo em X", combinados e lições aprendidas — para uma ajudar a outra e não pisarmos no pé uma da outra.

> **🚦 Status atual:** 🟢 livre — nenhuma IA trabalhando agora. · _atualizado por Claude · 2026-07-15_

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
