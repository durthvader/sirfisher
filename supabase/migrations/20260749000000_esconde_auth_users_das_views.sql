-- =====================================================================
-- Remove referencia direta a auth.users das views expostas na Data API
-- =====================================================================
--
-- O Security Advisor do Supabase (auth_users_exposed) sinalizou duas
-- views que fazem "left join auth.users" para exibir o nome de quem
-- cadastrou/recolheu/depositou/atualizou um registro:
--   - public.app_venda_especie_controle
--   - public.app_contas_recorrentes_pagamentos
--
-- Ambas ja sao restritas a authenticated (revoke de public/anon) e ja
-- filtram por papel no WHERE, mas o linter marca qualquer view com
-- referencia direta a auth.users acessivel a authenticated, porque a
-- Data API poderia em tese ser usada para tentar ler colunas alem do
-- nome pretendido.
--
-- Correcao: encapsular a leitura de auth.users numa funcao no schema
-- private (mesmo padrao ja usado no projeto, ver
-- 20260703120000_corrige_views_auth_security_invoker.sql), que so
-- devolve o nome de exibicao. As views passam a chamar a funcao em vez
-- de fazer join direto em auth.users. Comportamento visivel no app
-- nao muda.
-- =====================================================================

begin;

create or replace function private.nome_exibicao_usuario(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select initcap(coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name'))
  from auth.users u
  where u.id = p_user_id;
$$;

revoke all privileges on function private.nome_exibicao_usuario(uuid)
  from public, anon, authenticated;
grant execute on function private.nome_exibicao_usuario(uuid) to authenticated;

create or replace view public.app_venda_especie_controle
with (security_barrier = true, security_invoker = false) as
select
  v.id,
  v.data,
  v.unidade,
  v.valor,
  v.observacao,
  v.criado_em,
  v.recolhida_em,
  v.depositada_em,
  private.nome_exibicao_usuario(v.cadastrado_por) as cadastrado_por_nome,
  private.nome_exibicao_usuario(v.recolhida_por) as recolhida_por_nome,
  private.nome_exibicao_usuario(v.depositada_por) as depositada_por_nome
from public.venda_especie v
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

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
  private.nome_exibicao_usuario(p.atualizado_por) as atualizado_por_nome,
  p.atualizado_em
from public.conta_recorrente_pagamento p
join public.conta_recorrente c on c.id = p.conta_id
where public.usuario_pode_acessar_pagina('contas_recorrentes.html');

revoke all privileges on public.app_venda_especie_controle
  from public, anon, authenticated;
grant select on public.app_venda_especie_controle to authenticated;

revoke all privileges on public.app_contas_recorrentes_pagamentos
  from public, anon, authenticated;
grant select on public.app_contas_recorrentes_pagamentos to authenticated;

commit;
