# Canal de comunicação — Claude ⇄ Codex

Canal de recados entre as duas IAs que trabalham neste repositório (**Claude Code** e **Codex**). Serve para handoffs, avisos de "estou mexendo em X", combinados e lições aprendidas — para uma ajudar a outra e não pisarmos no pé uma da outra.

> **🚦 Status atual:** 🟢 livre — nenhuma IA trabalhando agora. · _atualizado por Claude · 2026-07-14_

## Protocolo
- **Ao começar uma tarefa:** ler este arquivo. As mensagens mais recentes ficam **no fim**.
- **Linha 🚦 Status (topo):** ao **começar**, marque 🔴 + sua área/arquivos + commit-base; ao **terminar**, volte para 🟢 livre. É a resposta rápida para "posso mexer agora?". Se estiver 🔴 de outra IA sem sinal de conclusão, parar e confirmar com o Rogério.
- **Ao terminar / entregar:** acrescentar uma mensagem curta no fim, no formato `## AAAA-MM-DD · <autor> — <assunto>`, dizendo **o que mexeu**, **o que ficou pendente** e qualquer coisa que a outra precise saber. Handoff inclui: arquivos alterados · migration criada (nº) e se aplicou · validações rodadas · estado do deploy · pendências/riscos.
- **Mantenha o canal enxuto:** guarde só a linha 🚦 Status + os **últimos ~3 recados**; pode podar os mais antigos ao deixar um recado novo (o `git` preserva tudo — `git log`/`git diff` recuperam o histórico). O que for regra durável vai para o `AGENTS.md`, não fica aqui. Assim a leitura custa ~o mesmo sempre.
- Isto **não substitui** o `AGENTS.md` (regras canônicas) nem os commits — é o "recado rápido" entre nós.
- Combinados fixos já viraram regra no `AGENTS.md` (checar `ls supabase/migrations/` antes de criar migration; migrations idempotentes; uma IA por vez na mesma branch).

---

**PENDÊNCIA aberta:** migration `20260738000000_cartao_credito_entra_dre_temporario.sql` (2026-07-07) é declaradamente temporária — a fatura de cartão BTG entra na DRE só nas fontes vivas até existir uma fonte de ETL com as compras itemizadas do BTG; quando essa fonte existir, reverter `entra_dre` para a expressão de `20260735000000` (senão a despesa duplica). Ver detalhes no `git log`/na própria migration.

## 2026-07-14 · Claude — entra_dre passa a excluir CONTABIL (receita e despesa)

Bug relatado pelo Rogério via index.html: "Lucro bruto (tend.)" (R$201 mil) maior que "Faturamento (tend.)" (R$190 mil) em julho. Causa raiz: fato_financeiro.entra_dre so excluia dre_grupo='TRANSFERENCIA' (categoria legada do historico); o grupo CONTABIL (que reune Transferencia entre Contas, Antecipação de Receita, ANALISAR INDIVIDUAL, estornado, pagamento devolvido) nunca foi excluido de forma geral — so despesas_reais/listar_despesas_dia do calendario.html tinham esse tratamento (20260739). Migration `20260748000000_entra_dre_exclui_contabil.sql`: recria fato_financeiro excluindo CONTABIL de entra_dre, MAS com carve-out explícito para a categoria `ANALISAR INDIVIDUAL` — são R$462 mil em despesa (134 lançamentos, 2022–2025, boa parte Pix para a própria empresa/coligadas e para os sócios) que nunca foram de fato classificados; não há confirmação de que sejam não-operacionais, então continuam entrando na DRE exatamente como antes. Corrige retroativamente receita/despesa/resultado em vários meses de 2022-2026 (fato_financeiro não é materializada). Mantém o TEMPORÁRIO do cartão de crédito (20260738) e a exclusão de TRANSFERENCIA (Depósito Dinheiro) intactos — validado antes do push que nenhum dos dois seria afetado pela troca.

**PENDÊNCIA nova:** os R$462 mil em `ANALISAR INDIVIDUAL` (2022-2025) precisam de classificação manual — não foram tocados por esta migration de propósito. Boa parte é Pix para "SIR FISHER COMERCIO DE ALIMENTOS LTDA" e para os sócios; vale investigar se são retirada/pró-labore, empréstimo entre empresas do grupo, ou despesa real mal categorizada.
— Claude


## 2026-07-14 · Codex — números inteiros no detalhamento do planejamento

Em `planejamento.html`, as colunas Meta, Realizado, Diferença e Atingimento do quadro Detalhamento passaram a ser arredondadas sem casas decimais e formatadas em `pt-BR`, com ponto como separador de milhar. Cards, gráfico e regras de cálculo não foram alterados. Validação estática e exemplos dos formatadores conferidos; navegador integrado indisponível para inspeção visual nesta sessão. Sem pendências de código.
— Codex


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
