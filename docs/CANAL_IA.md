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

## 2026-07-14 · Claude — corte só considera dia completo (tendências)

Migration nova: `20260745000000_corte_considera_dia_completo.sql` (idempotente, `create or replace view`). Muda a regra do corte de dados: `corte_venda` agora é `least(max Stone, max venda_especie, ontem em America/Sao_Paulo)` — um dia só entra na tendência quando cartão E espécie já passaram por ele e o dia terminou. `corte_caixa` ganha a trava de "ontem". `tendencia_mes` passa a usar `corte_venda.dia` direto como `dia_ref` (antes era `max(dia)` do mês, e espécie adiantada furava o corte). Motivo: sangria lançada à frente da base e importação no meio do dia distorciam as projeções (validado com dados reais de 14/07: o cenário estava ativo — corte no próprio dia 14 parcial — e segurar o corte em 13/07 muda a tendência de forma material; sem valores aqui, regra do AGENTS.md). Semântica combinada com o Rogério: buraco de espécie com lançamento posterior = zero implícito; buraco na fronteira = dia fica fora; R$ 0 explícito fecha o dia. Docs em `docs/supabase_schema.md`. Snapshot `mv_fluxo_caixa_diario` pega a correção no próximo `refresh_painel()`. Sem pendências.
— Claude


## 2026-07-14 · Claude — status.html monitora Extrato BS Cash

Migration nova: `20260746000000_status_cargas_inclui_bs_cash.sql` (idempotente, `create or replace function`). `private.ler_status_cargas()` ganhou um `union all` para `raw_bs_cash` (fonte "Extrato BS Cash", mesmo nome já usado no `log_carga` pelo `05_importar_bs_cash.py`) — a fonte estava fora do monitoramento do status.html. Sem mudança no front nem em `app_status_cargas`. Validado o SELECT do branch novo contra o banco antes do push. Sem pendências.
— Claude


## 2026-07-14 · Claude — corrige de-para do iFood Benefícios (vale-alimentação)

Bug relatado pelo Rogério via status.html: pagamentos do vale-alimentação (Pix para o CNPJ da Zoop/iFood Pago, 19.468.242/0001-32) estavam classificados como fornecedor "BDL Distribuidora Xarope" / categoria Bebidas / DESPESA DIRETA DE VENDA. Confirmado: esse CNPJ é sempre iFood Benefícios (nome varia entre "Zoop" e "Ifood Pago" no extrato); a maioria dos lançamentos do mesmo CNPJ já estava correta (fornecedor IFOOD BENEFÍCIOS, categoria Alimentação, grupo PESSOAL) — usei o mesmo padrão para corrigir os errados. Migration `20260747000000_corrige_classificacao_ifood_beneficios.sql` (dado, não schema): (1) `de_para` id 1410 (regra viva, cnpj) corrigida — resolve retroativamente os lançamentos do extrato Stone (2026); (2) UPDATE em `raw_historico` para as linhas de 2023-2026 que tinham a categoria gravada direto na linha. Conferido: nenhum `ajuste_manual` sobrepondo essas linhas. Sem pendências.
— Claude


## 2026-07-14 · Claude — entra_dre passa a excluir CONTABIL (receita e despesa)

Bug relatado pelo Rogério via index.html: "Lucro bruto (tend.)" (R$201 mil) maior que "Faturamento (tend.)" (R$190 mil) em julho. Causa raiz: fato_financeiro.entra_dre so excluia dre_grupo='TRANSFERENCIA' (categoria legada do historico); o grupo CONTABIL (que reune Transferencia entre Contas, Antecipação de Receita, ANALISAR INDIVIDUAL, estornado, pagamento devolvido) nunca foi excluido de forma geral — so despesas_reais/listar_despesas_dia do calendario.html tinham esse tratamento (20260739). Migration `20260748000000_entra_dre_exclui_contabil.sql`: recria fato_financeiro excluindo CONTABIL de entra_dre, MAS com carve-out explícito para a categoria `ANALISAR INDIVIDUAL` — são R$462 mil em despesa (134 lançamentos, 2022–2025, boa parte Pix para a própria empresa/coligadas e para os sócios) que nunca foram de fato classificados; não há confirmação de que sejam não-operacionais, então continuam entrando na DRE exatamente como antes. Corrige retroativamente receita/despesa/resultado em vários meses de 2022-2026 (fato_financeiro não é materializada). Mantém o TEMPORÁRIO do cartão de crédito (20260738) e a exclusão de TRANSFERENCIA (Depósito Dinheiro) intactos — validado antes do push que nenhum dos dois seria afetado pela troca.

**PENDÊNCIA nova:** os R$462 mil em `ANALISAR INDIVIDUAL` (2022-2025) precisam de classificação manual — não foram tocados por esta migration de propósito. Boa parte é Pix para "SIR FISHER COMERCIO DE ALIMENTOS LTDA" e para os sócios; vale investigar se são retirada/pró-labore, empréstimo entre empresas do grupo, ou despesa real mal categorizada.
— Claude


## 2026-07-14 · Codex — números inteiros no detalhamento do planejamento

Em `planejamento.html`, as colunas Meta, Realizado, Diferença e Atingimento do quadro Detalhamento passaram a ser arredondadas sem casas decimais e formatadas em `pt-BR`, com ponto como separador de milhar. Cards, gráfico e regras de cálculo não foram alterados. Validação estática e exemplos dos formatadores conferidos; navegador integrado indisponível para inspeção visual nesta sessão. Sem pendências de código.
— Codex
