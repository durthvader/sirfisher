-- =====================================================================
-- Atualizacao do painel sob demanda (so admin) via wrapper SECURITY DEFINER
-- =====================================================================
--
-- PROBLEMA
--   A pagina Despesas le mv_despesa_mensal (materialized view / snapshot),
--   materializada por performance (consultar fato_financeiro ao vivo leva
--   ~3s e estoura o statement_timeout). O snapshot so e refeito por
--   refresh_painel(), chamada ao fim de cada importacao
--   (scripts/importacao/importacao_core.py). Quando o usuario classifica
--   manualmente uma excecao ou uma transacao individual, fato_financeiro
--   (view ao vivo) ja reflete a categoria, mas o snapshot continua velho
--   ate a proxima importacao -> a pagina segue acusando "nao classificado"
--   em meses que ja foram classificados.
--
--   refresh_painel() foi restrita a service_role (migration
--   20260702210000_contem_acessos_publicos), entao um admin logado no
--   navegador (role authenticated) nao consegue dispara-la pela tela.
--
-- SOLUCAO
--   Wrapper SECURITY DEFINER public.solicitar_refresh_painel(), que:
--     - exige papel 'admin' (mesmo gate de definir_permissao_pagina);
--     - chama refresh_painel() internamente, executando como dono (postgres),
--       que mantem permissao de execucao mesmo apos o revoke de 20260702210000;
--     - fica exposta apenas a authenticated (o gate interno barra nao-admin);
--     - retorna o horario de conclusao (clock_timestamp) para a tela confirmar.
--   A permissao de service_role sobre refresh_painel() continua fechada; o
--   unico caminho novo e admin -> solicitar_refresh_painel -> refresh_painel.
--
-- OBJETOS
--   + public.solicitar_refresh_painel()  (nova funcao SECURITY DEFINER)
--
-- RISCO: baixo.
--   - Nao altera nenhum objeto existente; refresh_painel() nao muda.
--   - refresh_painel() ja roda REFRESH MATERIALIZED VIEW CONCURRENTLY (nao
--     bloqueia leituras) e leva poucos segundos; so admin pode acionar.
--   - refresh_painel() faz "set local statement_timeout = 0", entao a RPC
--     nao cai no timeout curto do role authenticated.
-- =====================================================================

begin;

create or replace function public.solicitar_refresh_painel()
returns timestamptz
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem atualizar o painel.';
  end if;

  perform public.refresh_painel();

  return clock_timestamp();
end;
$$;

revoke all privileges on function public.solicitar_refresh_painel() from public, anon, authenticated;
grant execute on function public.solicitar_refresh_painel() to authenticated;

commit;
