# Observabilidade e desempenho

Este documento orienta diagnósticos sem alterar dados financeiros, schema ou
regras de classificação.

## Rotina operacional

1. Consultar o Status do painel para identificar fontes atrasadas, falhas de
   carga e tarefas de atualização pendentes.
2. Consultar os advisors de segurança e desempenho do Supabase por leitura.
3. Para uma consulta lenta, capturar o período, a página/RPC envolvida e um
   `EXPLAIN (ANALYZE, BUFFERS)` em ambiente seguro antes de propor índice ou
   reescrita.
4. Registrar a decisão, a evidência e o impacto esperado antes de criar uma
   migration.

## Regras para índices

- Um alerta de chave estrangeira sem índice é candidato, não autorização para
  criar todos os índices de uma vez.
- Priorizar relações usadas em joins, filtros, exclusões ou rotinas demoradas.
- Um índice marcado sem uso só pode ser removido após período representativo de
  tráfego e revisão das rotinas mensais/administrativas.
- Toda criação ou remoção deve ocorrer em migration nova, idempotente e com
  validação de plano de execução.

## Segurança

As views `public.app_*` com `security_definer` e as tabelas com RLS sem policy
seguem decisões documentadas no `AGENTS.md`; não devem ser alteradas apenas
para silenciar o Security Advisor.

Funções `SECURITY DEFINER` usadas por endpoints autenticados exigem revisão por
amostragem sempre que forem criadas ou alteradas: `search_path` fixo, checagem
de papel/permissão dentro da função, grants mínimos e ausência de SQL dinâmico
inseguro.

## Sinais que exigem investigação

- timeout ou repetição de refresh;
- carga recusada, parcial ou com saldo não conciliado;
- fonte atrasada ou sem carga;
- query/RPC mais lenta que o orçamento de resposta da página;
- crescimento de exceções, classificações pendentes ou decisões de conciliação.

Nenhuma dessas situações autoriza reclassificar, excluir ou modificar dados
financeiros automaticamente.
