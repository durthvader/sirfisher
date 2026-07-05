# Autenticação Google e papéis de acesso

## Visão geral

O painel usa Google OAuth no front-end. A autenticação identifica o usuário e a
autorização é controlada pelo perfil interno e pelas permissões de cada página.
Uma conta Google sem perfil ativo vê a tela de acesso aguardando liberação e não
recebe dados financeiros.

Papéis disponíveis:

- `admin`: acesso irrestrito, inclusive às páginas administrativas
  `usuarios.html`, `status.html` e `permissoes.html`;
- `socio`: acesso aos painéis financeiros e às rotinas liberadas para o papel;
- `gerente`: acesso ao painel operacional `gerente.html` e às demais páginas
  liberadas para o papel, sem acesso automático aos dados financeiros
  detalhados reservados a admin e sócio.

O acesso de `socio` e `gerente` é configurado por página em
`public.pagina_permissao`. O admin sempre tem acesso a todas as páginas, e as
três páginas administrativas permanecem exclusivas do admin.

## Componentes

- `assets/auth.js`: login Google, guarda de rotas, logout, página inicial por
  papel e leitura das permissões;
- `public.perfil_usuario`: vínculo entre `auth.users`, papel interno e situação
  ativa do usuário;
- `public.pagina_permissao`: páginas liberadas para `socio` e `gerente`;
- `public.papel_usuario_atual()` e `public.usuario_tem_papel(text[])`: funções
  usadas pelas policies, funções e views;
- funções `private.ler_*`: leituras privilegiadas com validação de papel e
  `search_path` fixo;
- views `public.app_*`: endpoints protegidos consumidos pelo front-end;
- `public.definir_acesso_usuario(uuid, text, boolean)`: administração de papel
  e situação do usuário;
- `public.definir_permissao_pagina(text, text[])`: alteração das permissões de
  página;
- policies de `ajuste_manual`, `de_para` e `venda_especie`: escrita restrita a
  usuários autenticados e autorizados.

## Configuração do provedor Google

1. No Google Cloud, criar um cliente OAuth do tipo aplicação Web.
2. Cadastrar como URI de redirecionamento a callback exibida pelo provedor
   Google no painel do Supabase.
3. No Supabase, em Authentication > Providers > Google, informar Client ID e
   Client Secret e habilitar o provedor.
4. Em Authentication > URL Configuration, definir a URL publicada do GitHub
   Pages como Site URL e Redirect URL permitida, preservando o caminho do
   repositório e a barra final.
5. Desabilitar métodos de login que não serão usados. O front-end oferece apenas
   Google, mas a configuração do Supabase completa a política Google-only.
6. Nunca salvar Client Secret, tokens ou credenciais no repositório.

## Primeiro administrador

O provisionamento abaixo é necessário somente quando ainda não existe um admin
ativo. Primeiro, a conta deve entrar com Google para ser criada em `auth.users`.
Depois, no SQL Editor do Supabase, substituir o marcador pelo e-mail correto:

```sql
insert into public.perfil_usuario (user_id, papel, ativo)
select id, 'admin', true
from auth.users
where lower(email) = lower('<EMAIL_GOOGLE_DO_ADMIN>')
on conflict (user_id) do update
set papel = excluded.papel,
    ativo = excluded.ativo;
```

Após o provisionamento, sair e entrar novamente. Os demais usuários devem ser
administrados por `usuarios.html`, que chama `definir_acesso_usuario()` para
atribuir `admin`, `socio` ou `gerente`, desativar e reativar acessos. A RPC
impede remover ou rebaixar o último administrador ativo. Nunca conceder acesso
automaticamente apenas pelo domínio do e-mail.

As permissões de páginas para sócios e gerentes são administradas em
`permissoes.html`. A tela não permite retirar o acesso irrestrito do admin nem
liberar páginas administrativas para outros papéis.

## Segurança do banco

As migrations do repositório fecham o acesso anônimo, restringem
`authenticated` a uma allowlist de objetos e expõem ao front-end somente os
endpoints necessários. Novas mudanças de schema ou autorização devem ser feitas
em uma nova migration, sem editar nem reaplicar manualmente migrations antigas.

## Validação mínima

- sem sessão: a página inicial exibe somente “Continuar com Google”;
- conta sem perfil ativo: nenhuma consulta financeira é liberada;
- `gerente`: é direcionado a `gerente.html` quando a página está permitida e
  não abre páginas administrativas;
- `socio`: abre somente os painéis e rotinas configurados para o papel e não
  abre páginas administrativas;
- `admin`: abre todas as páginas, inclusive usuários, status e permissões;
- o menu e `rotinas.html` não mostram páginas sem permissão;
- logout: remove a sessão e retorna à tela de login;
- dashboards consultam somente endpoints protegidos `app_*`;
- chamadas com papel `anon` aos endpoints financeiros falham;
- console do navegador: sem erros nos fluxos acima.
