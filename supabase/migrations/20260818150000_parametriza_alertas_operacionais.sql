-- Parametriza janelas operacionais ainda fixas no front-end e faz o Status
-- acompanhar todas as integracoes importaveis que estejam ativas.

begin;

insert into public.parametros (chave, valor, descricao) values
  ('carga_dias_em_dia', 2, 'Prazo para considerar uma fonte em dia'),
  ('carga_dias_atencao', 5, 'Prazo para considerar uma fonte em atenção'),
  ('sangria_dias_recentes', 14, 'Dias recentes exibidos no controle de sangrias'),
  ('conta_recorrente_alerta_dias', 5, 'Antecedência do alerta de vencimento')
on conflict (chave) do nothing;

update public.parametros
set grupo = case
      when chave like 'carga_%' then 'Qualidade das cargas'
      else 'Operação'
    end,
    unidade_medida = 'dias',
    valor_min = case when chave = 'carga_dias_em_dia' then 0 else 1 end,
    valor_max = case
      when chave in ('sangria_dias_recentes', 'conta_recorrente_alerta_dias') then 90
      else 365
    end,
    ordem = case chave
      when 'carga_dias_em_dia' then 600
      when 'carga_dias_atencao' then 610
      when 'sangria_dias_recentes' then 620
      when 'conta_recorrente_alerta_dias' then 630
      else ordem
    end
where chave in (
  'carga_dias_em_dia',
  'carga_dias_atencao',
  'sangria_dias_recentes',
  'conta_recorrente_alerta_dias'
);

create or replace function private.validar_limites_status_carga()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, pg_temp
as $$
declare
  v_outro numeric;
begin
  if new.chave = 'carga_dias_em_dia' then
    select p.valor into v_outro
    from public.parametros p
    where p.chave = 'carga_dias_atencao';
    if v_outro is not null and new.valor >= v_outro then
      raise exception using errcode = '22023',
        message = 'O prazo em dia deve ser menor que o prazo de atencao.';
    end if;
  elsif new.chave = 'carga_dias_atencao' then
    select p.valor into v_outro
    from public.parametros p
    where p.chave = 'carga_dias_em_dia';
    if v_outro is not null and new.valor <= v_outro then
      raise exception using errcode = '22023',
        message = 'O prazo de atencao deve ser maior que o prazo em dia.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_limites_status_carga on public.parametros;
create trigger trg_validar_limites_status_carga
before insert or update of valor on public.parametros
for each row
when (new.chave in ('carga_dias_em_dia', 'carga_dias_atencao'))
execute function private.validar_limites_status_carga();

revoke all privileges on function private.validar_limites_status_carga()
from public, anon, authenticated;

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
stable
security definer
set search_path = pg_catalog, pg_temp
as $function$
  with cfg as (
    select
      (current_timestamp at time zone c.fuso_horario)::date as hoje,
      greatest(
        0,
        public.parametro_valor('carga_dias_em_dia', 2)::integer
      ) as dias_em_dia,
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
    case when b.ultima_importacao is null then null
         else greatest(cfg.hoje - b.ultima_importacao::date, 0) end::integer,
    case
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
  order by f.nome;
$function$;

revoke all privileges on function private.ler_status_cargas()
from public, anon, authenticated;
grant execute on function private.ler_status_cargas() to authenticated;

comment on function private.ler_status_cargas() is
  'Status das integracoes importaveis ativas, com nomes, fuso e prazos configurados.';

commit;
