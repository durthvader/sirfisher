# Implantação em uma nova empresa

Este roteiro cria uma instalação totalmente separada: repositório, Supabase,
autenticação, banco, dados e publicação próprios. Nenhuma base financeira deve
ser compartilhada entre empresas.

## 1. Criar a infraestrutura isolada

1. Criar um repositório GitHub novo a partir deste projeto, sem copiar branches
   de trabalho, arquivos locais, `.env`, `.mcp.json` ou dados exportados.
2. Criar um projeto Supabase novo e vincular o deploy de migrations à `main` do
   repositório novo.
3. Configurar GitHub Pages para usar o workflow `deploy-pages.yml`.
4. Confirmar que o domínio da instalação nova não aponta para o projeto atual.

## 2. Configuração de inicialização

O arquivo `assets/supabase-client.js` é a única configuração que não pode ser
alterada pela tela: o navegador precisa saber a qual Supabase se conectar antes
de conseguir abrir qualquer tela administrativa. Na cópia nova, substituir
somente a URL e a chave pública `anon` pelos valores do Supabase novo.

Nunca inserir nesse arquivo `service_role`, senha do banco, token pessoal ou
qualquer chave privada. Depois da troca, pesquisar pelo identificador do projeto
anterior e confirmar que ele não aparece na cópia nova.

## 3. Banco e autenticação

1. Aguardar a aplicação completa das migrations e conferir que a última versão
   do catálogo foi aplicada.
2. Configurar o provedor Google e as URLs de redirecionamento conforme
   `docs/AUTENTICACAO_GOOGLE.md`, usando somente domínio e credenciais novos.
3. Criar o primeiro administrador pelo procedimento documentado, sem versionar
   e-mail pessoal.
4. Ativar no painel do Supabase as proteções de autenticação aplicáveis,
   inclusive proteção contra senhas vazadas quando houver login por senha.

## 4. Parâmetros alteráveis pela interface

Entrar como administrador e revisar todos os cards de **Parâmetros**:

- identidade da empresa em **Parâmetros gerais**;
- parâmetros das projeções e do caixa;
- regras de recebimento e taxas;
- peso dos dias da semana;
- grupos de despesas variáveis;
- metas mensais e saldo inicial;
- nome exibido da unidade única, contas bancárias, fontes financeiras e contas Stone;
- permissões por página, usuários e papéis.

A identidade passa a ser usada automaticamente nos títulos, cabeçalhos e
mensagens de login das páginas. Alterações ficam auditadas no banco.

A instalação trabalha com uma única unidade operacional. O código técnico da
unidade é preservado para manter compatibilidade com o histórico; o nome
exibido é alterado em **Parâmetros gerais**. Bancos, adquirentes e códigos Stone
são contas/origens distintas vinculadas a essa mesma unidade.

## 5. Fontes e importação

Os importadores existentes cobrem os layouts já documentados em
`scripts/importacao/README.md`. Antes de usar outra adquirente, banco ou sistema,
validar o layout e criar um adaptador específico; não reaproveitar um importador
com colunas apenas parecidas.

1. Executar os dry-runs locais sem dados de produção no repositório.
2. Em **Parâmetros → Fontes financeiras**, vincular cada fonte à conta correta
   e definir se entra no faturamento, caixa e DRE.
3. Em **Parâmetros → Contas Stone**, vincular cada código Stone a uma conta da
   unidade única. O código não representa uma unidade.
4. Conferir cabeçalhos, datas, sinais, totais e regra de deduplicação.
5. Fazer a primeira carga em período pequeno e reconciliar com os relatórios da
   empresa nova antes de importar o histórico.
6. Nunca usar credenciais ou arquivos da instalação atual.

### Cadastros iniciais herdados

A cadeia histórica de migrations contém cadastros e regras que preservam o
comportamento da instalação atual. Eles não incluem os arquivos financeiros,
mas podem incluir nomes de contas, unidades, fornecedores, De/Para e padrões de
classificação que não servem para outra empresa.

Antes da primeira importação, revisar na interface administrativa todos esses
cadastros. Desativar ou remover regras que não pertencem à nova empresa; quando
um objeto ainda não tiver exclusão segura pela tela, fazer o ajuste em uma
migration nova exclusiva do repositório novo. Não editar migrations históricas.

## 6. Validação antes da abertura

Executar:

```powershell
python scripts\ci\check_project.py
python scripts\ci\test_migrations.py
python scripts\ci\test_access_contracts.py
python scripts\ci\test_importacao.py
```

Depois do deploy, testar em desktop e celular: login, perfis, navegação,
parâmetros, importação, atualização do painel e os principais totais. Só liberar
usuários após confirmar que nenhum dado, domínio ou identificador da instalação
anterior aparece na nova empresa.
