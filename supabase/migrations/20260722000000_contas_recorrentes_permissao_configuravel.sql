-- Faz Contas recorrentes obedecer a permissao configurada em pagina_permissao,
-- inclusive quando o administrador liberar a pagina para o papel gerente.

begin;

create or replace function public.usuario_pode_acessar_pagina(p_pagina text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select public.usuario_tem_papel(array['admin']::text[])
    or exists (
      select 1
      from public.perfil_usuario pu
      join public.pagina_permissao pp on pp.pagina = p_pagina
      where pu.user_id = auth.uid()
        and pu.ativo
        and pu.papel = any(pp.papeis)
    );
$function$;

revoke all privileges on function public.usuario_pode_acessar_pagina(text)
  from public, anon, authenticated;
grant execute on function public.usuario_pode_acessar_pagina(text) to authenticated;

-- Recria somente os gates das quatro RPCs operacionais. A importacao do
-- historico permanece exclusiva do admin.
do $migration$
declare
  v_funcao regprocedure;
  v_definicao text;
  v_nova_definicao text;
begin
  foreach v_funcao in array array[
    'public.listar_contas_recorrentes(date)'::regprocedure,
    'public.salvar_conta_recorrente(bigint,text,smallint,text,text,text,boolean,boolean)'::regprocedure,
    'public.salvar_pagamento_recorrente(bigint,date,numeric,text,date,boolean,text)'::regprocedure,
    'public.excluir_pagamento_recorrente(bigint,date)'::regprocedure
  ]
  loop
    select pg_get_functiondef(v_funcao) into v_definicao;
    v_nova_definicao := replace(
      v_definicao,
      'public.usuario_tem_papel(array[''admin'', ''socio'']::text[])',
      'public.usuario_pode_acessar_pagina(''contas_recorrentes.html''::text)'
    );
    if v_nova_definicao = v_definicao then
      raise exception 'Gate esperado nao encontrado em %.', v_funcao;
    end if;
    execute v_nova_definicao;
  end loop;
end
$migration$;

create or replace view public.app_contas_recorrentes_pagamentos
with (security_barrier = true, security_invoker = false) as
select
  p.id,
  p.conta_id,
  c.nome,
  c.categoria,
  c.tipo,
  c.unidade,
  p.competencia,
  p.situacao,
  p.valor,
  p.conta_bancaria,
  p.data_pagamento,
  p.observacao,
  p.origem,
  coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name')::text as atualizado_por_nome,
  p.atualizado_em
from public.conta_recorrente_pagamento p
join public.conta_recorrente c on c.id = p.conta_id
left join auth.users u on u.id = p.atualizado_por
where public.usuario_pode_acessar_pagina('contas_recorrentes.html');

create or replace view public.app_contas_recorrentes_totais
with (security_barrier = true, security_invoker = false) as
select
  p.competencia,
  sum(p.valor)::numeric(14,2) as total_pago,
  count(*)::integer as qtd_pagamentos
from public.conta_recorrente_pagamento p
join public.conta_recorrente c on c.id = p.conta_id
where p.situacao = 'pago'
  and c.tipo = 'despesa'
  and c.incluir_totais
  and public.usuario_pode_acessar_pagina('contas_recorrentes.html')
group by p.competencia;

revoke all privileges on public.app_contas_recorrentes_pagamentos
  from public, anon, authenticated;
revoke all privileges on public.app_contas_recorrentes_totais
  from public, anon, authenticated;
grant select on public.app_contas_recorrentes_pagamentos to authenticated;
grant select on public.app_contas_recorrentes_totais to authenticated;

commit;
