# AGENTS.md

## Contexto do projeto

Este é o projeto **sirfisher-app**, o painel financeiro do restaurante Sir Fisher. A aplicação usa front-end em HTML, CSS e JavaScript, scripts Python para importação de dados, Supabase/Postgres como camada de dados e GitHub Pages para publicação do front-end.

Este arquivo é a fonte canônica das instruções operacionais para qualquer IA que trabalhe no repositório, incluindo Claude Code e Codex. O `CLAUDE.md` importa este arquivo e deve conter apenas orientações exclusivas do Claude Code.

## Estrutura principal

- Páginas HTML na raiz: `index.html`, `vendas.html`, `caixa.html`, `despesas.html`, `dre.html`, `classificar_excecoes.html`, `analise_individual.html` e `venda_especie.html`.
- `scripts/importacao/`: scripts Python de importação e arquivos `.bat` usados para executar os fluxos locais.
- `supabase/`: migrations SQL e arquivos relacionados à estrutura do Supabase/Postgres. As migrations ficam em `supabase/migrations/`.
- `docs/`: documentação técnica, incluindo referências sobre o schema do Supabase.
- `.github/workflows/`: automações do GitHub Actions, incluindo o deploy do GitHub Pages.
- Arquivos de configuração relevantes: `.gitignore`, `.mcp.json`, `CLAUDE.md` e este `AGENTS.md`. O `.mcp.json` deve ser tratado como configuração local e seu conteúdo sensível nunca deve ser exposto.

## Regras obrigatórias antes de iniciar qualquer tarefa

1. Ler este `AGENTS.md` e o `CLAUDE.md`, se existir.
2. Executar `git status`.
3. Verificar se há arquivos modificados, staged ou untracked.
4. Não iniciar trabalho se houver alterações pendentes sem antes explicar ao usuário o estado encontrado e definir como preservá-las.
5. Com a árvore de trabalho limpa, executar `git pull origin main` antes de começar uma tarefa nova.
6. Confirmar que a branch ativa e o diretório do repositório são os esperados antes de editar arquivos.

## Regras de Git

- Apenas uma IA deve trabalhar no repositório por vez.
- Nunca trabalhar simultaneamente com Claude e Codex na mesma branch.
- Sempre terminar a tarefa executando `git status`.
- Adicionar e commitar apenas arquivos diretamente relacionados à tarefa.
- Usar mensagens de commit claras, específicas e compatíveis com a alteração realizada.
- Fazer push somente depois das validações aplicáveis e da revisão do conjunto de arquivos do commit.
- Não commitar arquivos sensíveis, CSVs, relatórios brutos, `.env`, `.env.*`, arquivos locais ou backups.
- Não usar comandos destrutivos para descartar alterações sem autorização explícita.
- Respeitar o trabalho existente no diretório e nunca sobrescrever mudanças de outra pessoa ou IA.

## Segurança e dados sensíveis

- Nunca expor chaves, tokens, senhas, URLs privadas, credenciais ou dados financeiros em respostas, logs, commits ou documentação.
- Nunca exibir conteúdo de CSV financeiro.
- Nunca commitar `.env`, `.env.*`, arquivos `*.local`, relatórios financeiros, CSVs, XLSX, XLS ou dados brutos.
- Respeitar integralmente o `.gitignore` e revisar `git status` antes de qualquer commit.
- Tratar chaves Supabase `service_role`, tokens, senhas e `DATABASE_URL` como segredos.
- Usar o acesso MCP ao Supabase apenas para leitura, análise de schema, tabelas, views e conferência de dados; não revelar configurações de conexão.
- Se um segredo aparecer acidentalmente, interromper a tarefa, não reproduzi-lo e orientar sua revogação ou rotação.

## Supabase e banco de dados

- Validar a regra de negócio e a origem dos dados antes de criar ou modificar dashboards, métricas ou consultas.
- Não executar SQL destrutivo sem aprovação explícita do usuário.
- Não alterar migrations antigas sem autorização explícita.
- Preferir uma nova migration em `supabase/migrations/` quando uma mudança estrutural for necessária.
- Antes de criar uma migration, explicar o problema, os objetos afetados, o SQL proposto e os riscos.
- Depois da revisão do usuário, as migrations devem seguir o fluxo normal de commit e push para `main`, onde são aplicadas pela integração do GitHub com o Supabase.
- Documentar qualquer alteração de schema, tabela, view, materialized view, function, trigger ou policy.
- Não assumir que uma divergência financeira é erro de código ou banco sem validar a origem, o período, a regra de cálculo e a completude dos dados.
- Não alterar diretamente o banco por ferramentas configuradas apenas para leitura.

## Front-end

- Manter compatibilidade com hospedagem estática no GitHub Pages.
- Evitar dependências desnecessárias e não introduzir etapas de build sem justificativa.
- Preservar a navegação e os links entre todas as páginas existentes.
- Testar visualmente no navegador quando possível, incluindo comportamento responsivo e mobile.
- Manter o padrão visual, os componentes, as cores e os comportamentos já usados no projeto.
- Antes de modificar HTML, CSS ou JavaScript, informar quais arquivos serão alterados.
- Verificar erros de console e fluxos principais após mudanças relevantes.

## Scripts Python e importação

- Não hardcodar caminhos absolutos, senhas, tokens, credenciais ou nomes de arquivos específicos de uma máquina.
- Não versionar CSVs, XLSX, XLS, relatórios exportados ou outros dados brutos.
- Preservar compatibilidade com os arquivos `.bat` existentes e com seus parâmetros esperados.
- Preferir argumentos de linha de comando, variáveis de ambiente e caminhos relativos portáveis.
- Validar a sintaxe dos scripts antes de finalizar, preferencialmente por leitura e parse quando não for desejável gerar `__pycache__`.
- Explicar qualquer mudança em regras de importação, transformação, classificação, deduplicação ou atualização de dados.
- Não executar importações contra ambientes reais sem aprovação explícita.

## Fluxo de alternância entre Claude e Codex

```text
Claude termina → git status → commit → push
Codex começa → git pull origin main → trabalha → commit → push
Claude volta → git pull origin main → continua
```

Antes de alternar a IA responsável, garantir que a tarefa anterior esteja validada, commitada e enviada, ou explicar claramente qualquer estado pendente.

## Checklist obrigatório ao finalizar tarefa

- Listar os arquivos alterados.
- Explicar objetivamente o que foi feito.
- Rodar todas as validações possíveis e informar seus resultados.
- Executar `git status` e relatar o estado final.
- Sugerir uma mensagem de commit adequada quando houver alterações prontas.
- Não fazer `git add`, commit ou push sem autorização, salvo quando o usuário pedir explicitamente.
- Confirmar que nenhum arquivo sensível, dado bruto ou alteração fora do escopo foi incluído.
