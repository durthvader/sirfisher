# Canal de comunicação — Claude ⇄ Codex

Canal de recados entre as duas IAs que trabalham neste repositório (**Claude Code** e **Codex**). Serve para handoffs, avisos de "estou mexendo em X", combinados e lições aprendidas — para uma ajudar a outra e não pisarmos no pé uma da outra.

## Protocolo
- **Ao começar uma tarefa:** ler este arquivo. As mensagens mais recentes ficam **no fim**.
- **Ao terminar / entregar:** acrescentar uma mensagem curta no fim, no formato `## AAAA-MM-DD · <autor> — <assunto>`, dizendo **o que mexeu**, **o que ficou pendente** e qualquer coisa que a outra precise saber.
- **Append-only:** não apague mensagens antigas. Se algo virou obsoleto, diga isso numa mensagem nova.
- Isto **não substitui** o `AGENTS.md` (regras canônicas) nem os commits — é o "recado rápido" entre nós.
- Combinados fixos já viraram regra no `AGENTS.md` (checar `ls supabase/migrations/` antes de criar migration; migrations idempotentes; uma IA por vez na mesma branch).

---

## 2026-07-05 · Claude — boas-vindas 👋

Oi, Codex! Sou a Claude. Como a gente às vezes acaba trabalhando no mesmo repo em paralelo, o Rogério pediu pra criarmos este canal — pra combinar as coisas e uma dar suporte à outra. Somos duas mãos do mesmo time (com o Rogério, três). 🤝

**Duas coisas que aconteceram hoje (pra não repetir):**

1. **Colisão de versão de migration.** Nós duas criamos `20260721000000_*.sql` (você: `contas_recorrentes`; eu: editores de parâmetros). O runner do Supabase aplica por número de versão, então a minha foi **pulada silenciosamente** (a versão já constava aplicada) — as RPCs não existiam apesar de "aplicada". Renumerei a minha para `20260723000000`. → Combinado: antes de criar migration, rodar `ls supabase/migrations/` (não só `git log`) e usar um número maior.

2. **Idempotência.** Deixei a sua `20260721000000_contas_recorrentes.sql` idempotente — só adicionei `if not exists` nos 2 `create table` e nos 2 `create index`. **Não toquei na sua lógica**; o resto já estava ótimo (`create or replace`, `revoke`/`grant`, `on conflict`, `enable rls`). Motivo: a checagem "Supabase Preview" reprocessa as migrations do zero e falhava com `conta_recorrente already exists` num re-run. Se você preferir outra abordagem, é só dizer aqui. (Produção intacta — a migration já estava aplicada e não re-roda.)

**O que entreguei hoje:** menu de conta do admin virou dropdown compacto no cabeçalho; botão "Atualizar painel" em Status (RPC `solicitar_refresh_painel`); hub de **Parâmetros** (`parametros.html`) + editores (`parametros_gerais.html` e o genérico `parametros_editor.html?t=<tabela>`) para 9 tabelas de config, via RPCs `admin_listar_*` / `admin_salvar_*` `SECURITY DEFINER` com gate de admin. Tudo aplicado, deploy e Supabase Preview verdes.

Deixo o repo **limpo e sincronizado com `origin/main`**. Bom trabalho, parceira! 🐟
— Claude
