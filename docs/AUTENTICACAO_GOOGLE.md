# Autenticação Google e papéis de acesso

## Objetivo

O painel usa exclusivamente Google OAuth no front-end. A autenticação identifica
o usuário; a autorização é controlada pela tabela `public.perfil_usuario`.

Papéis disponíveis:

- `gestor`: dashboards financeiros e rotinas operacionais;
- `operador`: somente classificação, análise individual e venda em espécie.

Uma conta Google autenticada sem perfil ativo vê a tela de acesso aguardando
liberação e não recebe dados financeiros.

## Componentes

- `assets/auth.js`: login Google, guarda de rotas, logout e telas por papel;
- `public.perfil_usuario`: vínculo entre `auth.users` e o papel interno;
- `public.papel_usuario_atual()`: retorna o papel da sessão;
- `public.usuario_tem_papel(text[])`: função usada pelas policies e views;
- funções `private.ler_*`: fazem a leitura privilegiada com papel validado e
  `search_path` fixo;
- views `public.app_*`: endpoints `security_invoker` protegidos consumidos pelo
  front-end;
- policies de `ajuste_manual`, `de_para` e `venda_especie`: escrita somente por
  usuário autenticado com papel `gestor` ou `operador`.

## Rollout seguro

### Etapa A — preparar o banco

Aplicar, nesta ordem, as migrations
`20260703030000_prepara_auth_google_e_papeis.sql` e
`20260703120000_corrige_views_auth_security_invoker.sql`. Elas criam os papéis e
os endpoints protegidos, mas mantêm temporariamente a leitura anônima dos
endpoints antigos dos dashboards. Assim, o site atual não é interrompido.

### Etapa B — configurar Google e Supabase

1. No Google Cloud, criar um cliente OAuth do tipo aplicação Web.
2. No cliente Google, cadastrar como URI de redirecionamento a callback exibida
   pelo provedor Google no painel do Supabase.
3. No Supabase, em Authentication > Providers > Google, informar Client ID e
   Client Secret e habilitar o provedor.
4. Em Authentication > URL Configuration, definir a URL publicada do GitHub
   Pages como Site URL e também como Redirect URL permitida, preservando o
   caminho do repositório e a barra final.
5. Não salvar Client Secret, tokens ou credenciais no repositório.

### Etapa C — publicar e provisionar o primeiro gestor

1. Publicar `assets/auth.js`, as oito páginas HTML e o workflow atualizado.
2. Entrar pela primeira vez com a conta Google que será gestora. A tela deve
   informar que o acesso aguarda liberação.
3. No SQL Editor do Supabase, substituir o marcador pelo e-mail Google correto e
   executar:

```sql
insert into public.perfil_usuario (user_id, papel, ativo)
select id, 'gestor', true
from auth.users
where lower(email) = lower('<EMAIL_GOOGLE_DO_GESTOR>')
on conflict (user_id) do update
set papel = excluded.papel,
    ativo = excluded.ativo;
```

4. Sair, entrar novamente e validar todos os dashboards e rotinas.
5. Para liberar outro usuário, repetir o provisionamento usando `gestor` ou
   `operador`. Nunca conceder papel automaticamente apenas pelo domínio do e-mail.

Depois da migration da fase 5, gestores também podem usar `usuarios.html`. A
tela lista contas presentes em `auth.users`, inclusive as pendentes, e chama a
RPC `definir_acesso_usuario()` para liberar, alterar o papel, desativar ou
reativar. A RPC impede que o último gestor ativo seja removido.

### Etapa D — fechar o legado anônimo

Somente depois de existir pelo menos um gestor validado, aplicar a migration
`20260703160000_fecha_acesso_anonimo.sql`. Ela remove de `anon` e `PUBLIC` os
privilégios em objetos do schema `public` e endurece os privilégios padrão de
objetos futuros. Essa migration final não deve ser aplicada antes do teste do
primeiro gestor, pois sua aplicação antecipada pode bloquear o painel.

Depois do fechamento anônimo, aplicar
`20260703170000_restringe_authenticated_a_allowlist.sql`. Ela remove grants
legados de `authenticated` e reabre explicitamente somente as views `app_*`, as
três rotinas operacionais e as funções de autorização usadas pelo aplicativo.

Depois do fechamento, desabilitar no Supabase os demais métodos de login que não
serão usados. O front-end já oferece apenas Google; a configuração do provedor é
o que torna a política Google-only completa.

## Validação mínima

- sem sessão: a página inicial exibe somente “Continuar com Google”;
- conta sem perfil: nenhuma consulta financeira é liberada;
- `operador`: abre as três rotinas operacionais e não abre dashboards;
- `gestor`: abre dashboards e rotinas;
- logout: remove a sessão e retorna à tela de login;
- console do navegador: sem erros nos fluxos acima;
- Network: dashboards consultam somente endpoints `app_*`;
- depois da Etapa D: chamadas com papel `anon` aos endpoints legados falham.
