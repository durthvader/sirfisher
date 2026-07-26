-- =====================================================================
-- HOTFIX: recria public.app_painel_fluxo_caixa
-- =====================================================================
--
-- PROBLEMA (regressao introduzida por mim na 20260765000000)
--   Aquela migration precisou recriar mv_saldo_caixa_diario_detalhado para
--   acrescentar a coluna saldo_inter e usou "drop materialized view ...
--   cascade". Antes disso levantei os dependentes da MV e recriei os
--   quatro que apareceram: app_gerente_saldo_variacao,
--   app_painel_saldo_atual, app_painel_saldo_fim_mes e painel_fluxo_caixa.
--
--   O erro: aquela consulta listou apenas os dependentes DIRETOS. O
--   cascade tambem derrubou o que dependia deles em segundo nivel --
--   app_painel_fluxo_caixa, que le painel_fluxo_caixa e nao a MV. Ela nao
--   foi recriada e ficou faltando no banco.
--
--   Efeito visivel: caixa.html consulta app_painel_fluxo_caixa e passou a
--   receber erro, mostrando "Nao foi possivel carregar a projecao de caixa
--   agora" no lugar da curva. As demais telas nao usam essa view, por isso
--   o problema so apareceu no grafico do caixa.
--
-- SOLUCAO
--   Recriar a view exatamente como estava definida na 20260706000000
--   (ultima versao antes da queda), com o mesmo conjunto de colunas, o
--   mesmo gate de papel e os mesmos grants do padrao app_*.
--
-- OBJETOS
--   + public.app_painel_fluxo_caixa (recriada; nada mais e tocado)
--
-- LICAO PARA A PROXIMA VEZ
--   Antes de um "drop ... cascade", levantar os dependentes de forma
--   RECURSIVA (pg_depend em varios niveis) e nao so o primeiro nivel, ou
--   simplesmente evitar o cascade quando a intencao e apenas trocar
--   colunas de uma MV. Registrado em docs/CANAL_IA.md.
--
-- RISCO: baixo. Restaura o estado anterior; sem mudanca de regra.
-- =====================================================================

create or replace view public.app_painel_fluxo_caixa
with (security_barrier = true, security_invoker = false) as
  select dia, tipo, saldo, saldo_real, saldo_projetado, entrada_projetada,
         saida_projetada, resultado_dia
  from public.painel_fluxo_caixa s
  where public.usuario_tem_papel(array['admin', 'socio']);

comment on view public.app_painel_fluxo_caixa is
  'Fluxo de caixa diario exposto ao painel (admin/socio); recriada apos queda em cascata na 20260765000000.';

revoke all privileges on table public.app_painel_fluxo_caixa
  from public, anon, authenticated;
grant select on public.app_painel_fluxo_caixa to authenticated;
