# Baseline do Supabase

Este diretório concentra os artefatos necessários para iniciar um projeto
Supabase vazio sem copiar dados financeiros nem reaplicar cegamente toda a
história evolutiva.

Arquivos:

- `database.types.ts`: contrato do schema `public` exposto pela API do
  Supabase, incluindo tabelas, views, relacionamentos e funções;
- `manifest.json`: contagens do catálogo e checksum SHA-256 do contrato;
- `regenerate.ps1`: comandos para regenerar o contrato e, quando a Supabase CLI
  estiver vinculada ao projeto, produzir um dump DDL sem dados.
- `schema.sql`: dump estrutural de `public` e `private` (ainda não gerado);
- `bootstrap_config.sql`: seed neutro dos cadastros indispensáveis, sem
  transações, usuários ou dados financeiros (ainda não gerado).

O arquivo de tipos foi gerado diretamente pela introspecção do Supabase. Ele é
adequado para detectar drift no contrato público da API, mas não substitui um
dump DDL. As contagens históricas do manifesto cobrem `public` e `private`; o
schema `private` não é exposto pelo arquivo de tipos.

No estado atual, o diretório **não é suficiente para inicializar um banco
vazio**: faltam `schema.sql` e `bootstrap_config.sql`. Isso é deliberadamente
tratado como bloqueio pelo pré-flight, evitando uma implantação aparentemente
bem-sucedida com tabelas ou parâmetros ausentes.

`regenerate.ps1` produz o DDL e registra no manifesto a última migration já
incluída no snapshot. O seed neutro precisa ser montado e revisado à parte: ele
deve conter somente identidade genérica, unidade, parâmetros, regras e
permissões iniciais. Nunca incluir tabelas `raw_*`, movimentos, usuários,
históricos, fornecedores ou saldos da empresa atual.

As migrations existentes continuam sendo a fonte de evolução. Ao restaurar um
snapshot, as versões até `migration_cutoff` precisam ser marcadas como
aplicadas no projeto novo; `migration repair` altera apenas o histórico, não
executa o SQL. Não editar migrations antigas para fazê-las coincidir com o
baseline.

Referências oficiais:

- https://supabase.com/docs/guides/api/rest/generating-types
- https://supabase.com/docs/reference/cli/supabase-db-dump
