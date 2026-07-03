# Inventário de objetos sem consumidor confirmado

Data da análise: 2026-07-03.

## Objetivo e método

Este inventário apoia a limpeza futura do banco sem executar alterações. Foram
cruzadas três evidências:

1. referências nos arquivos ativos do repositório, desconsiderando migrations,
   documentação e o contrato de tipos gerado;
2. dependências entre views registradas no catálogo do Postgres;
3. metadados de existência e estimativa de linhas, sem consultar dados
   financeiros.

Ausência nessas fontes não prova que um objeto esteja sem uso. Consumidores
externos, consultas manuais, jobs e integrações fora do repositório podem não
aparecer na análise. Por isso, nenhum comando `DROP` foi criado ou executado.

## Candidatos de alta confiança para revisão

| Objeto | Tipo | Evidência | Ação recomendada |
| --- | --- | --- | --- |
| `backup_grants_20260629` | tabela | sem referência no código e sem dependente identificado | confirmar retenção do backup e, só então, propor migration de remoção |
| `backup_policies_20260629` | tabela | sem referência no código e sem dependente identificado | confirmar retenção do backup e, só então, propor migration de remoção |

Os nomes indicam artefatos de uma operação de segurança realizada em
2026-06-29. A eventual remoção deve ocorrer em migration nova e somente após
confirmar que o rollback histórico não depende deles.

## Views sem consumidor confirmado no repositório

As views abaixo não têm referência no front-end ou nos scripts ativos e não
possuem outra view dependente identificada:

- `conciliacao_stone_resumo`
- `painel_dre_executivo`
- `painel_meta_real_mensal`
- `painel_tendencia_diaria`
- `painel_venda_mes_atual`
- `saldo_mensal`
- `saldo_stone_atual`
- `vendas_diaria`

`conciliacao_stone_resumo` deve ser preservada enquanto a fase de conciliação
estiver prevista no roadmap. As demais precisam de confirmação funcional e de
uma janela de observação antes de qualquer proposta de remoção.

## Tabelas que exigem investigação adicional

- `conta`: possui consumidores confirmados nos importadores Stone e Banco do
  Brasil; não é candidata à remoção.
- `unidade`: o conceito é usado no fluxo de venda em espécie e pode participar
  de relacionamentos do banco; preservar até mapear chaves estrangeiras e
  integrações.
- `metas`: não apareceu no código ativo, mas está semanticamente ligada às
  views de metas; preservar até validar a funcionalidade planejada.

## Próximo passo seguro

Antes de remover qualquer objeto:

1. confirmar com o responsável funcional se ele ainda é necessário;
2. verificar consumidores externos e logs de uso por uma janela acordada;
3. mapear chaves estrangeiras, funções, policies e permissões relacionadas;
4. preparar migration nova, reversível quando possível;
5. revisar e aprovar o SQL antes de aplicá-lo.
