# Inventário de objetos sem consumidor confirmado

Primeira análise: 2026-07-03. Reauditado em 2026-08-14.

## Objetivo e método

Este inventário apoia a limpeza do banco. São cruzadas três evidências
independentes:

1. dependência entre relações registrada no catálogo (`pg_depend` +
   `pg_rewrite`), que pega views e materialized views;
2. citação em corpo de função de `public` ou `private`
   (`pg_get_functiondef` com limite de palavra `\m...\M`) — o passo que a
   análise de 2026-07-03 não fazia e que evita remover objeto usado só por RPC;
3. referência exata nos arquivos ativos do repositório — páginas HTML,
   `assets/`, `scripts/importacao/` e `scripts/ci/` — desconsiderando
   migrations e documentação, que registram o histórico.

Vale também conferir a ACL: objeto sem `grant` para `anon` ou `authenticated`
nunca esteve exposto na Data API, o que elimina a hipótese de consumidor
externo por REST.

Cuidado ao buscar por substring: `app_conciliacao_stone_resumo` casa dentro de
`app_conciliacao_stone_resumo_mensal`, e `admin_salvar_conta` dentro de
`admin_salvar_conta_com_saldo`. Falso positivo aí faz o objeto parecer vivo.

## Removidos em 2026-08-14 (`20260818200000_remove_objetos_sem_consumidor.sql`)

Todos passaram nos três critérios com resultado zero e tinham ACL apenas para
`postgres` e `service_role`.

| Objeto | Tipo | Motivo |
| --- | --- | --- |
| `mv_saldo_caixa_diario_detalhado` | materialized view | aposentada em `20260818120000`; ficou congelada em 11/08/2026 parecendo dado vivo e induziu a diagnóstico errado |
| `painel_dre_executivo` | view | sem consumidor desde a análise de 2026-07-03 |
| `painel_tendencia_diaria` | view | idem |
| `painel_venda_mes_atual` | view | idem |
| `saldo_mensal` | view | idem |
| `saldo_stone_atual` | view | idem |
| `vendas_diaria` | view | idem |
| `app_gerenciador_de_para` | view | a página passou a usar a RPC `listar_regras_de_para` |
| `detalhar_saldo_caixa_dia(date)` | função | substituída por `listar_saldo_contas_dia(date)` |
| `importar_contas_recorrentes_legado(jsonb, jsonb)` | função | carga legada já feita; seguia com `execute` para `authenticated` e escrevendo em massa |
| `admin_salvar_conta(...)` | função | sobrecarga antiga de `admin_salvar_conta_com_saldo` |
| `admin_salvar_fonte_financeira(...)` | função | sobrecarga antiga |
| `admin_salvar_fonte_financeira_com_saldo(...)` | função | sobrecarga antiga de `..._com_vigencia` |

A migration reconfere as dependências no banco antes de remover qualquer coisa
e aborta a transação inteira se algum alvo tiver ganhado consumidor. Os `drop`
são `restrict` (sem `cascade`) e `if exists`, então a migration é
re-executável. As definições continuam no histórico de migrations.

## Preservados de propósito

- `conciliacao_stone_resumo`, `private.ler_conciliacao_stone_resumo` e
  `app_conciliacao_stone_resumo`: sem consumidor hoje, mantidos enquanto a fase
  de conciliação estiver no roadmap.
- `painel_colchao_despesa_fixa`: sem consumidor no front-end, mas é a memória de
  cálculo de `projecao_despesa_fixa`. Serve para conferir a projeção quando ela
  divergir — foi o objeto que explicou o erro corrigido em `20260818180000`.
  Marcada como diagnóstica no comentário do próprio objeto.
- `admin_listar_saldo_inicial` / `admin_salvar_saldo_inicial`: sem chamador no
  editor de parâmetros, mas a tabela `saldo_inicial` continua viva (tem view
  dependente e função que a lê). Decidir sobre a tabela antes das RPCs.

## Pendente de decisão do responsável

| Objeto | Tipo | Tamanho | Observação |
| --- | --- | --- | --- |
| `backup_grants_20260629` | tabela | 264 kB | estado das permissões antes da operação de segurança de 2026-06-29 |
| `backup_policies_20260629` | tabela | 16 kB | estado das policies na mesma data |

São **dados**, não derivados: diferente das views, não dá para recriar a partir
das migrations. A remoção depende de confirmar que nenhum rollback histórico
depende delas. Nenhum `DROP` foi preparado para elas.

## Tabelas que exigem investigação adicional

- `unidade`: o conceito é usado no fluxo de venda em espécie e pode participar
  de relacionamentos do banco; preservar até mapear chaves estrangeiras.
- `metas`: não apareceu no código ativo, mas está semanticamente ligada às
  views de metas; preservar até validar a funcionalidade planejada.
- `conta`: possui consumidores confirmados nos importadores Stone e Banco do
  Brasil; não é candidata à remoção.

## Antes de remover qualquer outro objeto

1. rodar os três critérios acima e conferir a ACL;
2. confirmar com o responsável funcional se o objeto ainda é necessário;
3. mapear chaves estrangeiras, funções, policies e permissões relacionadas;
4. preparar migration nova, com verificação prévia de dependência e `drop`
   sem `cascade`;
5. revisar e aprovar o SQL antes de aplicá-lo.
