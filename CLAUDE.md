@AGENTS.md

# Instruções específicas para Claude Code

- O `AGENTS.md` importado acima é a fonte canônica das regras do projeto.
- Quando necessário, use `/memory` para confirmar que este arquivo e o `AGENTS.md` foram carregados na sessão.

## Autorização permanente para commit e push

- O usuário autorizou Claude Code a commitar e dar push (para `main`) das alterações que ele mesmo pediu neste repositório, sem pedir confirmação a cada vez. Essa autorização está configurada de fato em `.claude/settings.local.json` (bloco `autoMode.allow`) — uma nota aqui no CLAUDE.md sozinha não é suficiente para o classificador de modo automático liberar o push.
- Isso não dispensa nenhuma outra regra do `AGENTS.md`: revisar `git status`/`git diff` antes de commitar, incluir apenas arquivos relacionados à tarefa, nunca commitar segredos/dados sensíveis/CSVs/XLSX, mensagens de commit claras, e relatar o `git status` final.
- Ações destrutivas (reset --hard, force push, descartar alterações, editar migrations antigas, etc.) continuam exigindo autorização explícita a cada vez.
