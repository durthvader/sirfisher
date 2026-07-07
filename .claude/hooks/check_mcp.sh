#!/usr/bin/env bash
# SessionStart hook: reporta o status dos MCP servers do projeto (ex: Supabase),
# já que o status de conexão as vezes não reflete quais ferramentas ficam
# realmente expostas dentro da sessão em andamento.
out=$(claude mcp list 2>&1)
if echo "$out" | grep -q '✗\|not connected\|Not connected'; then
  msg="MCP: há servidor(es) não conectado(s) — rode 'claude mcp list' para detalhes."
else
  linhas=$(echo "$out" | grep '✔' | sed 's/"/\\"/g' | tr '\n' ';')
  msg="MCP OK: ${linhas}Se uma ferramenta mcp__ não aparecer disponivel mesmo assim, pode ser preciso reiniciar a sessao."
fi
printf '{"systemMessage":"%s"}' "$msg"
