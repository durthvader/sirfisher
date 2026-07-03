# Baseline do Supabase

Este diretório registra o contrato reproduzível do schema observado em
2026-07-03, sem modificar migrations antigas e sem incluir dados.

Arquivos:

- `database.types.ts`: contrato do schema `public` exposto pela API do
  Supabase, incluindo tabelas, views, relacionamentos e funções;
- `manifest.json`: contagens do catálogo e checksum SHA-256 do contrato;
- `regenerate.ps1`: comandos para regenerar o contrato e, quando a Supabase CLI
  estiver vinculada ao projeto, produzir um dump DDL sem dados.

O arquivo de tipos foi gerado diretamente pela introspecção do Supabase. Ele é
adequado para detectar drift no contrato público da API, mas não substitui
sozinho um dump DDL para restauração. As contagens do manifesto cobrem os
schemas `public` e `private`; o schema `private` não é exposto no contrato da
API. O dump `schema.sql` deve ser produzido pela Supabase CLI em uma máquina
autenticada e nunca deve conter dados ou credenciais.

As migrations existentes continuam sendo a fonte de evolução após este ponto.
Não editar migrations antigas para fazê-las coincidir com o baseline.

Referências oficiais:

- https://supabase.com/docs/guides/api/rest/generating-types
- https://supabase.com/docs/reference/cli/supabase-db-dump
