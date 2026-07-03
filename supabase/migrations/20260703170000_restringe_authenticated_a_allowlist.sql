-- =====================================================================
-- Restringe authenticated a allowlist do aplicativo
-- =====================================================================
--
-- Remove grants legados que permitiam a qualquer usuario autenticado acessar
-- objetos internos diretamente. Em seguida, concede somente os endpoints app_*,
-- as operacoes usadas pelo front e as funcoes de autorizacao.
--
-- Nao altera dados nem privilegios de service_role.
-- =====================================================================

begin;

grant usage on schema public to authenticated;

revoke all privileges on all tables in schema public
  from authenticated;

revoke all privileges on all sequences in schema public
  from authenticated;

revoke all privileges on all functions in schema public
  from authenticated;

-- Perfil proprio e endpoints protegidos de leitura.
grant select on table public.perfil_usuario to authenticated;

grant select on table
  public.app_painel_resumo_mensal,
  public.app_painel_composicao_despesa,
  public.app_painel_saldo_fim_mes,
  public.app_painel_saldo_atual,
  public.app_painel_margem_contribuicao,
  public.app_painel_ultima_carga,
  public.app_painel_cargas,
  public.app_painel_diario,
  public.app_painel_recebimento_resumo,
  public.app_painel_recebimento_canal,
  public.app_painel_recebimento_hora,
  public.app_painel_fluxo_caixa,
  public.app_recebimento_conhecido,
  public.app_recebimento_projetado,
  public.app_projecao_despesa_fixa,
  public.app_projecao_despesa_direta,
  public.app_painel_saldo_por_conta,
  public.app_painel_dre_cascata,
  public.app_mv_despesa_mensal,
  public.app_analise_individual,
  public.app_excecoes,
  public.app_categoria_dre
to authenticated;

-- Escritas operacionais permitidas; as policies continuam validando o papel.
grant select, insert, update on table public.ajuste_manual to authenticated;
grant insert on table public.de_para to authenticated;
grant select, insert, update on table public.venda_especie to authenticated;

grant usage, select on sequence public.ajuste_manual_id_seq to authenticated;
grant usage, select on sequence public.de_para_id_seq to authenticated;
grant usage, select on sequence public.venda_especie_id_seq to authenticated;

grant execute on function public.papel_usuario_atual() to authenticated;
grant execute on function public.usuario_tem_papel(text[]) to authenticated;

-- Objetos futuros exigem concessao explicita em migration revisada.
alter default privileges in schema public
  revoke all privileges on tables from authenticated;

alter default privileges in schema public
  revoke all privileges on sequences from authenticated;

alter default privileges in schema public
  revoke all privileges on functions from authenticated;

commit;
