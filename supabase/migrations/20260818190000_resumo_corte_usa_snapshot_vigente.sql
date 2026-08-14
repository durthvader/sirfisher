-- =====================================================================
-- resumo_corte_caixa() olha o snapshot vigente, não o aposentado
-- =====================================================================
--
-- PROBLEMA
--   A RPC criada em 20260818180000 lê `public.mv_saldo_caixa_diario_detalhado`
--   para dizer se o snapshot diário de saldo ficou atrás do corte de caixa.
--   Essa materialized view foi APOSENTADA em 20260818120000: as views e
--   funções migraram para `private.saldo_caixa_diario` /
--   `private.mv_saldo_conta_diario`, e `refresh_painel()` e
--   `private.processar_virada_financeira()` deixaram de atualizá-la -- aquela
--   migration inclusive proíbe que voltem a citá-la.
--
--   A MV antiga ficou no banco congelada no último refresh anterior
--   (11/08/2026) e nunca mais anda. Resultado: o aviso do Calendário
--   acusaria snapshot atrasado para sempre, mesmo com tudo em dia. Conferido:
--   `private.mv_saldo_conta_diario` está em 13/08/2026, igual ao corte.
--
-- SOLUÇÃO
--   A RPC passa a ler `private.mv_saldo_conta_diario`, que é o snapshot que
--   `private.validar_saldo_diario_materializado()` exige alinhado ao corte.
--   O sinal continua útil: se um `refresh_painel()` falhar, a MV fica para
--   trás e o aviso aparece com razão.
--
-- OBJETO
--   ~ public.resumo_corte_caixa()  -- mesma assinatura e colunas
--
-- RISCO: baixo. Só troca a relação lida em uma subquery de leitura. Sem
--   mudança de assinatura, colunas, grants ou de qualquer regra financeira.
--   Nenhuma tabela ou MV é alterada; a MV aposentada não é removida aqui.
-- =====================================================================

begin;

create or replace function public.resumo_corte_caixa()
returns table (
  corte_caixa date,
  snapshot_saldo date,
  dias_apos_corte integer,
  resultado_apos_corte numeric
)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  return query
  select ct.dia,
         (select max(s.dia) from private.mv_saldo_conta_diario s),
         coalesce((
           select count(*) from public.caixa_real_diario c where c.dia > ct.dia
         ), 0)::integer,
         coalesce((
           select round(sum(c.resultado_real), 2)
           from public.caixa_real_diario c where c.dia > ct.dia
         ), 0::numeric)
  from public.corte_caixa ct;
end;
$function$;

revoke all privileges on function public.resumo_corte_caixa() from public, anon;
grant execute on function public.resumo_corte_caixa() to authenticated;

do $validacao$
declare
  v_def text := pg_get_functiondef('public.resumo_corte_caixa()'::regprocedure);
begin
  if position('mv_saldo_caixa_diario_detalhado' in v_def) > 0 then
    raise exception 'resumo_corte_caixa ainda lê o snapshot aposentado.';
  end if;

  if position('private.mv_saldo_conta_diario' in v_def) = 0 then
    raise exception 'resumo_corte_caixa não lê o snapshot vigente por conta.';
  end if;
end;
$validacao$;

comment on function public.resumo_corte_caixa() is
  'Posição do corte de caixa, do snapshot vigente (private.mv_saldo_conta_diario) e do que já foi lançado depois do corte; alimenta o aviso do Calendário.';

commit;
