-- Fonte encerrada desce para o fim da lista de status.
--
-- Depois de 20260818210000 a fonte encerrada deixou de acumular atraso, mas
-- continuava ordenada por nome no meio das que ainda são cobradas. Quem olha o
-- painel quer ver primeiro o que exige ação; o que está encerrado é consulta.
--
-- Só muda o ORDER BY da função. Mesma assinatura, mesmas colunas, mesmos
-- valores -- nenhuma regra de situação, atraso ou carga é alterada.

begin;

create or replace function private.ler_status_cargas()
returns table (
  fonte text, linhas bigint, periodo_inicio date, periodo_fim date,
  ultima_importacao timestamptz, ultima_carga timestamptz,
  atraso_dias integer, situacao text
)
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $function$
  with cfg as (
    select
      (current_timestamp at time zone c.fuso_horario)::date as hoje,
      greatest(0, public.parametro_valor('carga_dias_em_dia', 2)::integer) as dias_em_dia,
      greatest(
        public.parametro_valor('carga_dias_atencao', 5)::integer,
        public.parametro_valor('carga_dias_em_dia', 2)::integer + 1
      ) as dias_atencao
    from public.configuracao_operacional c
    where c.singleton
  ), bases as (
    select 'stone_extrato'::text chave, 'Extrato Stone'::text fonte_log,
           count(*)::bigint linhas,
           min(e.data_hora)::date periodo_inicio,
           max(e.data_hora)::date periodo_fim,
           max(e.importado_em) ultima_importacao
    from public.raw_stone_extrato e
    union all
    select 'stone_vendas', 'Vendas Stone', count(*)::bigint,
           min(v.data_venda)::date, max(v.data_venda)::date, max(v.importado_em)
    from public.raw_stone_vendas v
    union all
    select 'stone_recebiveis', 'Recebíveis Stone', count(*)::bigint,
           min(coalesce(r.data_vencimento, r.data_venda::date)),
           max(coalesce(r.data_vencimento, r.data_venda::date)), max(r.importado_em)
    from public.raw_stone_recebiveis r
    union all
    select 'bb', 'Extrato BB', count(*)::bigint,
           min(b.data), max(b.data), max(b.importado_em)
    from public.raw_bb b
    union all
    select 'bs_cash', 'Extrato BS Cash', count(*)::bigint,
           min(c.data_hora)::date, max(c.data_hora)::date, max(c.importado_em)
    from public.raw_bs_cash c
    union all
    select 'inter', 'Extrato Inter', count(*)::bigint,
           min(i.data), max(i.data), max(i.importado_em)
    from public.raw_inter i
    union all
    select 'fundopay', 'Vendas Fundopay', count(*)::bigint,
           min(f.data_venda)::date, max(f.data_venda)::date, max(f.importado_em)
    from public.raw_fundopay_vendas f
  ), logs as (
    select l.fontes as fonte_log, max(l.data_hora) as ultima_carga
    from public.log_carga l
    group by l.fontes
  )
  select
    f.nome as fonte,
    b.linhas,
    b.periodo_inicio,
    b.periodo_fim,
    b.ultima_importacao,
    l.ultima_carga,
    case when f.encerrada_em is not null then null
         when b.ultima_importacao is null then null
         else greatest(cfg.hoje - b.ultima_importacao::date, 0) end::integer,
    case
      when f.encerrada_em is not null then 'encerrada'
      when b.ultima_importacao is null then 'sem carga'
      when cfg.hoje - b.ultima_importacao::date <= cfg.dias_em_dia then 'em dia'
      when cfg.hoje - b.ultima_importacao::date <= cfg.dias_atencao then 'atenção'
      else 'atrasada'
    end::text
  from bases b
  join public.fonte_financeira f on f.chave = b.chave and f.ativa
  left join logs l on l.fonte_log = b.fonte_log
  cross join cfg
  where public.usuario_tem_papel(array['admin']::text[])
  order by (f.encerrada_em is not null), f.nome;
$function$;

comment on function private.ler_status_cargas() is
  'Situação de carga por fonte; fonte com encerrada_em aparece como encerrada, não acumula atraso e desce para o fim da lista.';

do $validacao$
declare
  v_def text := pg_get_functiondef('private.ler_status_cargas()'::regprocedure);
begin
  if position('order by (f.encerrada_em is not null), f.nome' in lower(v_def)) = 0 then
    raise exception 'A ordenação das fontes encerradas não foi aplicada.';
  end if;
  if position('''encerrada''' in v_def) = 0 then
    raise exception 'A situação encerrada sumiu da função de status.';
  end if;
end;
$validacao$;

commit;
