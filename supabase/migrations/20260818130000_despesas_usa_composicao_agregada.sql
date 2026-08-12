-- Reduz a carga inicial de despesas.html reutilizando a composicao mensal
-- agregada que ja abastece o resumo. A fonte detalhada continua protegida e
-- sera consultada apenas para os meses efetivamente abertos pelo usuario.

begin;

create or replace view public.app_painel_composicao_despesa
with (security_barrier = true, security_invoker = false) as
select s.mes,
       s.ano_mes,
       s.grupo,
       s.valor
from public.painel_composicao_despesa s
where public.usuario_pode_acessar_alguma_pagina(array[
  'index.html',
  'despesas.html'
]::text[]);

revoke all privileges on table public.app_painel_composicao_despesa
  from public, anon, authenticated;
grant select on table public.app_painel_composicao_despesa
  to authenticated;

comment on view public.app_painel_composicao_despesa is
  'Composicao mensal agregada para Resumo e Despesas, sujeita a permissao configuravel das paginas.';

do $validation$
begin
  if not has_table_privilege(
    'authenticated',
    'public.app_painel_composicao_despesa',
    'SELECT'
  ) then
    raise exception 'authenticated perdeu SELECT em app_painel_composicao_despesa';
  end if;

  if has_table_privilege(
    'anon',
    'public.app_painel_composicao_despesa',
    'SELECT'
  ) then
    raise exception 'anon nao pode ler app_painel_composicao_despesa';
  end if;
end;
$validation$;

commit;
