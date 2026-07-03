# Fase 5 — qualidade e produto

## Entregas

- `usuarios.html`: gestão de contas Google e papéis, exclusiva para gestores;
- `qualidade.html`: cobertura, atraso e última importação das quatro fontes;
- `conciliacao.html`: conciliação Stone entre venda e recebível;
- `planejamento.html`: meta mensal versus faturamento realizado;
- workflow `Quality gates`: Python, JavaScript, links, contratos Supabase,
  segredos, artefato Pages e dry-runs sintéticos dos importadores.

## Segurança dos acessos

E-mails continuam sendo propriedade de `auth.users`; não são duplicados em
`perfil_usuario`. A leitura administrativa ocorre por função no schema
`private`, com `search_path` fixo e validação do papel `gestor`.

A escrita usa `public.definir_acesso_usuario()`. A função:

- aceita somente os papéis `gestor` e `operador`;
- exige que o chamador seja gestor ativo;
- valida a existência do usuário no Supabase Auth;
- impede desativar ou rebaixar o último gestor ativo;
- não exclui usuários nem históricos.

## Qualidade das cargas

O atraso é calculado pela última importação registrada nas tabelas brutas:

- até 2 dias: `em dia`;
- de 3 a 5 dias: `atenção`;
- acima de 5 dias: `atrasada`;
- sem importação: `sem carga`.

A data final de recebíveis pode estar no futuro porque representa agenda, não
erro de carga.

## Conciliação

O painel usa `conciliacao_stone` e `conciliacao_stone_resumo`, cuja chave é o
`STONE ID`, para comparar venda e agenda de recebíveis.

A ligação automática entre recebível e extrato bancário não foi implementada.
As fontes atuais não possuem uma chave estável confirmada para essa relação;
parear apenas por valor e data criaria falsos positivos. O extrato bancário é
monitorado no painel de qualidade até existir um identificador confiável ou um
relatório de liquidação que faça essa ponte.

## Planejamento

O orçamento versus realizado usa `painel_meta_real_mensal`. Na validação de
origem, a série de metas e realizados possuía cobertura contínua e valores não
nulos. Meses futuros são apresentados como planejados e não entram no acumulado
realizado do ano corrente.

## Contratos de banco

A migration `20260703200000_fase5_qualidade_produto.sql` cria os endpoints:

- `app_usuarios_acesso`;
- `app_qualidade_cargas`;
- `app_conciliacao_stone_resumo`;
- `app_conciliacao_stone`;
- `app_painel_meta_real_mensal`;
- RPC `definir_acesso_usuario(uuid, text, boolean)`.

Todos os endpoints são negados a `PUBLIC` e `anon`; `authenticated` recebe
somente os grants necessários e a regra de negócio ainda valida o papel gestor.
