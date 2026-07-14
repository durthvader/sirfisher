-- =====================================================================
-- status.html passa a monitorar tambem o Extrato BS Cash
-- =====================================================================
--
-- PROBLEMA
--   A pagina status.html le app_status_cargas -> private.ler_status_cargas(),
--   que monitora apenas 4 fontes (Extrato Stone, Vendas Stone, Recebiveis
--   Stone e Extrato BB). O BS Cash ficou de fora, apesar de o importador
--   05_importar_bs_cash.py ja gravar em raw_bs_cash (com importado_em e
--   data_hora) e registrar no log_carga com fontes = 'Extrato BS Cash'.
--
-- SOLUCAO
--   Recriar private.ler_status_cargas() identica, acrescentando um union
--   all para raw_bs_cash no CTE bases. O join com log_carga ja funciona
--   pelo nome 'Extrato BS Cash'; o front nao precisa de mudanca (renderiza
--   o que a view devolver).
--
-- OBJETOS AFETADOS
--   ~ private.ler_status_cargas() (create or replace; mesma assinatura,
--     mesmos tipos de retorno, mesmas clausulas de seguranca)
--
-- RISCO: baixo. Somente uma linha a mais no resultado; app_status_cargas
--   e grants permanecem intactos.
-- =====================================================================

create or replace function private.ler_status_cargas()
returns table(
  fonte text,
  linhas bigint,
  periodo_inicio date,
  periodo_fim date,
  ultima_importacao timestamp with time zone,
  ultima_carga timestamp with time zone,
  atraso_dias integer,
  situacao text
)
language sql
stable security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
  with bases as (
    select 'Extrato Stone'::text fonte, count(*)::bigint linhas,
           min(e.data_hora)::date periodo_inicio, max(e.data_hora)::date periodo_fim,
           max(e.importado_em) ultima_importacao
    from public.raw_stone_extrato e
    union all
    select 'Vendas Stone', count(*)::bigint,
           min(v.data_venda)::date, max(v.data_venda)::date, max(v.importado_em)
    from public.raw_stone_vendas v
    union all
    select 'Recebíveis Stone', count(*)::bigint,
           min(coalesce(r.data_vencimento, r.data_venda::date)),
           max(coalesce(r.data_vencimento, r.data_venda::date)), max(r.importado_em)
    from public.raw_stone_recebiveis r
    union all
    select 'Extrato BB', count(*)::bigint,
           min(b.data), max(b.data), max(b.importado_em)
    from public.raw_bb b
    union all
    select 'Extrato BS Cash', count(*)::bigint,
           min(c.data_hora)::date, max(c.data_hora)::date, max(c.importado_em)
    from public.raw_bs_cash c
  ), logs as (
    select l.fontes fonte, max(l.data_hora) ultima_carga
    from public.log_carga l
    group by l.fontes
  )
  select
    b.fonte,
    b.linhas,
    b.periodo_inicio,
    b.periodo_fim,
    b.ultima_importacao,
    l.ultima_carga,
    case when b.ultima_importacao is null then null
         else greatest(current_date - b.ultima_importacao::date, 0) end::integer,
    case
      when b.ultima_importacao is null then 'sem carga'
      when current_date - b.ultima_importacao::date <= 2 then 'em dia'
      when current_date - b.ultima_importacao::date <= 5 then 'atenção'
      else 'atrasada'
    end::text
  from bases b
  left join logs l on l.fonte = b.fonte
  where public.usuario_tem_papel(array['admin']::text[])
  order by b.fonte;
$function$;
