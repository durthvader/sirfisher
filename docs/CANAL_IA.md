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
