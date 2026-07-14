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

## 2026-07-07 · Claude — TEMPORÁRIO: fatura de cartão entra na DRE

Migration `20260738000000_cartao_credito_entra_dre_temporario.sql`: recria `fato_financeiro` mudando só a expressão de `entra_dre` — o grupo CARTÃO DE CRÉDITO passa a entrar na DRE nas fontes vivas (`origem <> 'historico'`); histórico 2022–2025 segue excluído (compras podem estar itemizadas lá; fatura dobraria). Motivo: nenhuma fonte importa as compras itemizadas do BTG, então ~R$ 18 mil de 2026 estavam invisíveis nos painéis. **Rollback planejado**: quando a fatura itemizada do BTG entrar no ETL, reverter para a expressão de `20260735000000`. Snapshots materializados atualizados após o apply.
— Claude

## 2026-07-07 · Claude — calendário deixa de contar CONTABIL como despesa

Bug relatado pelo Rogério: transferências Stone→BS Cash de 02/06 (17k+10k) contavam como despesa no calendário e a saída real (folha BS Cash 03/06) contava de novo. Duas causas: (1) "Transferencia entre Contas" mapeia p/ dre_grupo CONTABIL e o entra_dre de fato_financeiro só exclui TRANSFERENCIA (nome do histórico) — a exclusão nunca alcançou dados vivos; mv_despesa_mensal já excluía CONTABIL, o calendário não. (2) os dois Pix tinham ajuste_manual "Folha Salarial" (PESSOAL), inflando junho também no painel de Despesas. Correções: migration `20260739000000_calendario_exclui_contabil.sql` (despesas_reais do calendário e listar_despesas_dia excluem CONTABIL, mesma regra do mv) + update nos 2 registros de ajuste_manual (785/786 → Transferencia entre Contas) + refresh_painel(). Atenção futura: entra_dre NÃO exclui CONTABIL; quem consumir fato_financeiro p/ despesa deve excluir CONTABIL explicitamente.
— Claude


## 2026-07-14 · Claude — corte só considera dia completo (tendências)

Migration nova: `20260745000000_corte_considera_dia_completo.sql` (idempotente, `create or replace view`). Muda a regra do corte de dados: `corte_venda` agora é `least(max Stone, max venda_especie, ontem em America/Sao_Paulo)` — um dia só entra na tendência quando cartão E espécie já passaram por ele e o dia terminou. `corte_caixa` ganha a trava de "ontem". `tendencia_mes` passa a usar `corte_venda.dia` direto como `dia_ref` (antes era `max(dia)` do mês, e espécie adiantada furava o corte). Motivo: sangria lançada à frente da base e importação no meio do dia distorciam as projeções (validado com dados reais de 14/07: o cenário estava ativo — corte no próprio dia 14 parcial — e segurar o corte em 13/07 muda a tendência de forma material; sem valores aqui, regra do AGENTS.md). Semântica combinada com o Rogério: buraco de espécie com lançamento posterior = zero implícito; buraco na fronteira = dia fica fora; R$ 0 explícito fecha o dia. Docs em `docs/supabase_schema.md`. Snapshot `mv_fluxo_caixa_diario` pega a correção no próximo `refresh_painel()`. Sem pendências.
— Claude


## 2026-07-14 · Claude — status.html monitora Extrato BS Cash

Migration nova: `20260746000000_status_cargas_inclui_bs_cash.sql` (idempotente, `create or replace function`). `private.ler_status_cargas()` ganhou um `union all` para `raw_bs_cash` (fonte "Extrato BS Cash", mesmo nome já usado no `log_carga` pelo `05_importar_bs_cash.py`) — a fonte estava fora do monitoramento do status.html. Sem mudança no front nem em `app_status_cargas`. Validado o SELECT do branch novo contra o banco antes do push. Sem pendências.
— Claude
