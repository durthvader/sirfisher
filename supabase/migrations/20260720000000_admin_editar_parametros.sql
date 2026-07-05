-- =====================================================================
-- Edicao de public.parametros pela tela admin (parametros_gerais.html)
-- =====================================================================
--
-- PROBLEMA
--   A tabela parametros guarda os knobs das projecoes (% despesa direta,
--   horizonte do caixa, provisao de estoque, etc.) e hoje so e editavel
--   por SQL. Queremos edita-la pela pagina admin.
--
-- POR QUE RPC (e nao RLS na tabela)
--   parametros tem RLS ON e uma policy prem_sel_param (SELECT/public USING
--   true) que e LOAD-BEARING: as views fluxo_caixa_diario, painel_diario e
--   projecao_despesa_direta leem parametros e, pela cadeia security_invoker,
--   dependem dessa policy para funcionar para papeis nao-admin (Caixa/DRE/
--   Planejamento do gerente/socio). Trocar a policy arriscaria quebrar essas
--   telas. Entao NAO mexemos em grants/policies da tabela: expomos duas RPCs
--   SECURITY DEFINER com gate de admin (mesmo padrao de definir_permissao_pagina
--   e solicitar_refresh_painel). A tabela continua trancada para o navegador.
--
-- OBJETOS
--   + public.admin_listar_parametros()             (SECURITY DEFINER, admin)
--   + public.admin_salvar_parametro(text, numeric) (SECURITY DEFINER, admin)
--
-- RISCO: baixo. Nao altera a tabela nem as views; so adiciona duas funcoes
--   restritas a admin. Edita apenas a coluna valor de uma chave existente
--   (nao cria/apaga chaves, que sao estruturais e lidas pelas funcoes).
-- =====================================================================

begin;

create or replace function public.admin_listar_parametros()
returns setof public.parametros
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem ver os parametros.';
  end if;
  return query select * from public.parametros order by chave;
end;
$$;

create or replace function public.admin_salvar_parametro(p_chave text, p_valor numeric)
returns public.parametros
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_row public.parametros;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem alterar parametros.';
  end if;
  if p_valor is null then
    raise exception using errcode = '22023', message = 'Valor obrigatorio.';
  end if;

  update public.parametros set valor = p_valor
  where chave = p_chave
  returning * into v_row;

  if not found then
    raise exception using errcode = '22023', message = 'Parametro desconhecido: ' || coalesce(p_chave, '(nulo)');
  end if;

  return v_row;
end;
$$;

revoke all privileges on function public.admin_listar_parametros() from public, anon, authenticated;
grant execute on function public.admin_listar_parametros() to authenticated;

revoke all privileges on function public.admin_salvar_parametro(text, numeric) from public, anon, authenticated;
grant execute on function public.admin_salvar_parametro(text, numeric) to authenticated;

commit;
