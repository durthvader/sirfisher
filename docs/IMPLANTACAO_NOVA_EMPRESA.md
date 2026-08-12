# Implantação em uma nova empresa

Este roteiro mantém repositório, Supabase, autenticação, banco e publicação
totalmente separados. Não reutilize projeto, credenciais, usuários ou arquivos
financeiros da instalação atual.

## Situação do pacote de instalação

O front-end já possui troca validada de URL/chave e um pré-flight automatizado.
O banco ainda não está pronto para nascer vazio: as migrations versionadas são
uma história de evolução e pressupõem objetos anteriores ao repositório.

Antes da primeira implantação nova, ainda precisam ser gerados e revisados:

- `supabase/baseline/schema.sql`, dump DDL atual sem dados;
- `supabase/baseline/bootstrap_config.sql`, seed neutro de parâmetros,
  permissões e cadastros indispensáveis.

Enquanto qualquer um estiver ausente, o pré-flight falha de propósito. Não
vincule a integração GitHub/Supabase do cliente novo antes de resolver esses
dois itens, pois ela tentaria aplicar a cadeia histórica sobre um banco vazio.

## 1. Gerar o baseline na instalação de origem

Em uma máquina autenticada na Supabase CLI e vinculada ao projeto de origem:

```powershell
supabase\baseline\regenerate.ps1 -ProjectRef <PROJECT_REF_ATUAL>
```

O script atualiza os tipos, gera somente o DDL de `public` e `private` e grava
no manifesto a `migration_cutoff`. Revise o arquivo antes de commitar: ele não
pode conter `COPY`, linhas financeiras, URLs de conexão, senhas ou chaves.

Monte depois `bootstrap_config.sql` somente com defaults genéricos. Ele deve
incluir identidade, configuração operacional, uma unidade, parâmetros e
permissões iniciais; contas e fontes podem começar vazias e ser cadastradas na
tela. Não exporte dados de tabelas `raw_*`, movimentos, usuários, fornecedores,
históricos, contas a pagar ou saldos atuais.

## 2. Criar infraestrutura isolada

1. Criar um repositório GitHub novo a partir deste projeto, sem `.env`,
   `.mcp.json`, backups, CSV, XLSX ou branches de trabalho.
2. Criar um projeto Supabase novo, mas ainda não conectar sua integração ao
   GitHub.
3. Configurar GitHub Pages para usar `deploy-pages.yml`.
4. Confirmar que domínio, OAuth e repositório não apontam para a empresa atual.

## 3. Configurar o front-end

O navegador precisa saber qual Supabase consultar antes de abrir uma tela de
parâmetros; por isso URL e chave pública são a única configuração que não pode
viver no próprio banco. Troque ambas com:

```powershell
python scripts\implantacao\preparar_nova_empresa.py configurar `
  --url https://<PROJECT_REF_NOVO>.supabase.co `
  --chave-publica <CHAVE_PUBLISHABLE_OU_ANON>
```

O utilitário aceita somente URL HTTPS padrão e chave `publishable`/`anon`,
confere se URL e JWT pertencem ao mesmo projeto e nunca exibe a chave. Ele
rejeita `service_role` e chaves secretas.

## 4. Inicializar e reconciliar o banco novo

1. Aplicar `schema.sql` no banco vazio usando uma conexão mantida fora do
   repositório.
2. Aplicar `bootstrap_config.sql`.
3. Vincular a Supabase CLI ao **project ref novo** e conferir o destino antes de
   continuar.
4. Marcar como aplicadas somente as migrations até a `migration_cutoff` do
   manifesto. O comando oficial é `supabase migration repair <versões>
   --status applied`; ele corrige o histórico sem executar novamente o SQL.
5. Executar `supabase migration list` e `supabase db push --dry-run`. O dry-run
   deve listar apenas migrations posteriores ao snapshot, ou nenhuma.
6. Só então ativar a integração GitHub/Supabase do repositório novo.

Nunca executar `migration repair` sem conferir visualmente o project ref e sem
ter aplicado integralmente o snapshot. A referência oficial está em
<https://supabase.com/docs/guides/deployment/database-migrations>.

## 5. Autenticação e configuração pela tela

1. Configurar Google OAuth e URLs novas conforme `AUTENTICACAO_GOOGLE.md`.
2. Criar o primeiro administrador pelo procedimento documentado.
3. Entrar em **Parâmetros** e revisar identidade, operação, projeções, regras de
   recebimento, pesos, grupos variáveis, metas, contas, saldos, fontes e contas
   Stone.
4. Revisar usuários e permissões por página.

A instalação trabalha com uma unidade operacional. Banco, adquirente e origem
são contas/fontes distintas vinculadas a essa unidade; Stone não representa
estabelecimento.

## 6. Fontes, primeira carga e validação

Os importadores existentes são adaptadores de layouts específicos. Antes de
usar outro banco ou adquirente, valide o arquivo e crie um adaptador próprio;
nomes de provedores no importador são técnicos, não identidade da empresa.

Execute primeiro todos os testes locais:

```powershell
python scripts\ci\check_project.py
python scripts\ci\test_migrations.py
python scripts\ci\test_access_contracts.py
python scripts\ci\test_importacao.py
python scripts\ci\test_implantacao.py
python scripts\ci\test_financial_contracts.py
python scripts\ci\test_frontend_contracts.py
python scripts\implantacao\preparar_nova_empresa.py validar `
  --project-ref <PROJECT_REF_NOVO>
```

Faça a primeira importação em um período pequeno e reconcilie cabeçalhos,
datas, sinais, deduplicação e totais antes do histórico. Depois do deploy,
teste desktop e celular: login, perfis, navegação, parâmetros, importação,
atualização, calendário e principais números. Só libere usuários quando o
pré-flight estiver verde e nenhum identificador da instalação anterior aparecer.
