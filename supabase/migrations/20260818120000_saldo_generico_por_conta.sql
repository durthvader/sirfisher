-- Saldo por conta configurável, sem nomes de banco ou unidade na regra.
--
-- A estrutura antiga permanece durante a transição. Antes de trocar qualquer
-- consumidor, esta migration guarda o snapshot atual e exige que o novo motor
-- reproduza todos os dias e componentes centavo a centavo. Qualquer diferença
-- cancela a transação inteira.

begin;

-- A conta define como seu saldo é reconstruído. A fonte financeira informa
-- qual adaptador técnico fornece os movimentos. Assim, nome e banco ficam
-- livres para cada instalação e podem ser alterados na tela administrativa.
alter table public.conta
  add column if not exists saldo_metodo text not null default 'ignorar',
  add column if not exists saldo_data_base date not null default date '0001-01-01',
  add column if not exists saldo_base numeric not null default 0;

do $constraints$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.conta'::regclass
       and conname = 'conta_saldo_metodo_check'
  ) then
    alter table public.conta
      add constraint conta_saldo_metodo_check
      check (saldo_metodo = any (array['ignorar', 'extrato', 'movimentos']::text[]));
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.conta'::regclass
       and conname = 'conta_saldo_base_finito_check'
  ) then
    alter table public.conta
      add constraint conta_saldo_base_finito_check
      check (saldo_base not in ('Infinity'::numeric, '-Infinity'::numeric));
  end if;
end;
$constraints$;

comment on column public.conta.saldo_metodo is
  'Como reconstruir o saldo: ignorar, último saldo do extrato ou saldo-base somado aos movimentos.';
comment on column public.conta.saldo_data_base is
  'Fechamento que já está contido em saldo_base; somente movimentos posteriores são somados.';
comment on column public.conta.saldo_base is
  'Saldo conhecido no fechamento de saldo_data_base.';

alter table public.fonte_financeira
  add column if not exists saldo_adaptador text not null default 'nenhum';

do $constraints$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.fonte_financeira'::regclass
       and conname = 'fonte_financeira_saldo_adaptador_check'
  ) then
    alter table public.fonte_financeira
      add constraint fonte_financeira_saldo_adaptador_check
      check (
        saldo_adaptador = any (
          array[
            'nenhum', 'stone_extrato', 'bb', 'inter', 'bs_cash',
            'venda_especie'
          ]::text[]
        )
      );
  end if;
end;
$constraints$;

comment on column public.fonte_financeira.saldo_adaptador is
  'Formato técnico que alimenta o saldo da conta; nenhum quando a fonte não calcula saldo.';

-- Um adaptador ativo de caixa só pode alimentar uma fonte, evitando que o
-- mesmo extrato seja somado duas vezes por erro de configuração.
create unique index if not exists uq_fonte_saldo_adaptador_caixa
  on public.fonte_financeira (saldo_adaptador)
  where ativa and entra_caixa and saldo_adaptador <> 'nenhum';

-- Valores iniciais são vinculados pelas chaves técnicas das integrações, não
-- pelos nomes exibidos. Os WHERE preservam uma configuração já migrada caso o
-- arquivo seja reexecutado.
update public.fonte_financeira
   set saldo_adaptador = chave
 where chave = any (array['stone_extrato', 'bb', 'inter', 'bs_cash', 'venda_especie']::text[])
   and saldo_adaptador = 'nenhum';

insert into public.conta (nome, banco, unidade_id, ativa)
select
  'Dinheiro a depositar',
  'Dinheiro',
  c.unidade_principal_id,
  true
from public.configuracao_operacional c
where c.singleton
on conflict (nome) do nothing;

update public.fonte_financeira f
   set conta_id = (
         select c.id
           from public.conta c
          where c.nome = 'Dinheiro a depositar'
          order by c.id
          limit 1
       ),
       atualizado_em = now()
 where f.saldo_adaptador = 'venda_especie'
   and f.conta_id is null;

update public.conta c
   set saldo_metodo = 'extrato'
 where c.saldo_metodo = 'ignorar'
   and exists (
     select 1
       from public.fonte_financeira f
      where f.conta_id = c.id
        and f.saldo_adaptador = any (array['stone_extrato', 'bs_cash']::text[])
   );

update public.conta c
   set saldo_metodo = 'movimentos'
 where c.saldo_metodo = 'ignorar'
   and exists (
     select 1
       from public.fonte_financeira f
      where f.conta_id = c.id
        and f.saldo_adaptador = any (array['bb', 'inter', 'venda_especie']::text[])
   );

update public.conta c
   set saldo_data_base = si.data_base,
       saldo_base = si.saldo
  from public.fonte_financeira f
  join public.saldo_inicial si on lower(si.conta) = lower(f.chave)
 where f.conta_id = c.id
   and f.saldo_adaptador = 'bb'
   and c.saldo_data_base = date '0001-01-01'
   and c.saldo_base = 0;

-- O snapshot legado é a trava de segurança da conversão. Nada financeiro é
-- escrito; as tabelas temporárias desaparecem ao final da transação.
create temporary table saldo_generico_antes
on commit drop
as
select
  s.dia,
  s.saldo_stone,
  s.saldo_bb,
  s.saldo_inter,
  s.dinheiro_pendente,
  s.variacao_dinheiro_pendente,
  s.saldo_total
from public.mv_saldo_caixa_diario_detalhado s;

create temporary table saldo_anchor_antes
on commit drop
as
select
  s.data_ref,
  s.saldo_stone,
  s.saldo_bb,
  s.saldo_total,
  s.dinheiro_pendente
from public.saldo_anchor s;

-- Normaliza somente os formatos de entrada. A regra de saldo abaixo não sabe
-- o nome da empresa, da conta ou do banco.
create or replace view private.movimento_saldo_conta as
with cfg as (
  select
    public.unidade_principal_nome() as unidade,
    coalesce(
      (
        select c.fuso_horario
          from public.configuracao_operacional c
         where c.singleton
         limit 1
      ),
      current_setting('TimeZone')
    ) as fuso
)
select
  f.saldo_adaptador as adaptador,
  e.id::bigint as movimento_id,
  f.conta_id,
  e.data_hora::date as dia,
  e.data_hora as momento,
  e.valor,
  e.saldo_depois as saldo_reportado
from public.fonte_financeira f
cross join public.raw_stone_extrato e
where f.ativa and f.entra_caixa
  and f.saldo_adaptador = 'stone_extrato'
  and f.conta_id is not null

union all

select
  f.saldo_adaptador,
  b.id::bigint,
  f.conta_id,
  b.data,
  b.data::timestamp,
  b.valor,
  null::numeric
from public.fonte_financeira f
cross join public.raw_bb b
where f.ativa and f.entra_caixa
  and f.saldo_adaptador = 'bb'
  and f.conta_id is not null

union all

select
  f.saldo_adaptador,
  i.id::bigint,
  f.conta_id,
  i.data,
  i.data::timestamp,
  i.valor,
  null::numeric
from public.fonte_financeira f
cross join public.raw_inter i
where f.ativa and f.entra_caixa
  and f.saldo_adaptador = 'inter'
  and f.conta_id is not null

union all

select
  f.saldo_adaptador,
  b.id::bigint,
  f.conta_id,
  b.data_hora::date,
  b.data_hora,
  b.valor,
  b.saldo
from public.fonte_financeira f
cross join public.raw_bs_cash b
where f.ativa and f.entra_caixa
  and f.saldo_adaptador = 'bs_cash'
  and f.conta_id is not null

union all

select
  f.saldo_adaptador,
  v.id::bigint,
  f.conta_id,
  v.data,
  v.data::timestamp,
  v.valor,
  null::numeric
from public.fonte_financeira f
cross join cfg
join public.venda_especie v on v.unidade = cfg.unidade
where f.ativa and f.entra_caixa
  and f.saldo_adaptador = 'venda_especie'
  and f.conta_id is not null

union all

select
  f.saldo_adaptador,
  v.id::bigint,
  f.conta_id,
  (v.depositada_em at time zone cfg.fuso)::date,
  v.depositada_em at time zone cfg.fuso,
  -v.valor,
  null::numeric
from public.fonte_financeira f
cross join cfg
join public.venda_especie v
  on v.unidade = cfg.unidade
 and v.depositada_em is not null
where f.ativa and f.entra_caixa
  and f.saldo_adaptador = 'venda_especie'
  and f.conta_id is not null;

revoke all privileges on table private.movimento_saldo_conta
  from public, anon, authenticated;

comment on view private.movimento_saldo_conta is
  'Adaptadores de extrato normalizados em movimentos e saldos reportados por conta configurada.';

create materialized view if not exists private.mv_saldo_conta_diario
as
with corte as (
  select c.dia as fim
    from public.corte_caixa c
   limit 1
), contas_caixa as (
  select distinct
    c.id as conta_id,
    c.nome as conta,
    c.saldo_metodo,
    c.saldo_data_base,
    c.saldo_base
  from public.conta c
  join public.fonte_financeira f on f.conta_id = c.id
  where c.ativa
    and c.saldo_metodo <> 'ignorar'
    and f.ativa
    and f.entra_caixa
    and f.saldo_adaptador <> 'nenhum'
), limites as (
  select
    coalesce(
      min(m.dia) filter (
        where c.saldo_metodo = 'extrato'
          and m.saldo_reportado is not null
      ),
      min(m.dia),
      (select ct.fim from corte ct)
    ) as inicio,
    (select ct.fim from corte ct) as fim
  from private.movimento_saldo_conta m
  join contas_caixa c on c.conta_id = m.conta_id
), dias as (
  select gs::date as dia
  from limites l
  cross join lateral generate_series(
    l.inicio::timestamp,
    l.fim::timestamp,
    interval '1 day'
  ) gs
  where l.inicio is not null
    and l.fim is not null
    and l.fim >= l.inicio
), movimentos_antes as (
  select m.conta_id, sum(m.valor) as total
  from private.movimento_saldo_conta m
  join contas_caixa c on c.conta_id = m.conta_id
  cross join limites l
  where m.dia < l.inicio
    and m.dia > c.saldo_data_base
  group by m.conta_id
), movimentos_dia as (
  select m.conta_id, m.dia, sum(m.valor) as total
  from private.movimento_saldo_conta m
  join contas_caixa c on c.conta_id = m.conta_id
  cross join limites l
  where m.dia >= l.inicio
    and m.dia <= l.fim
    and m.dia > c.saldo_data_base
  group by m.conta_id, m.dia
), reportado_dia as (
  select distinct on (m.conta_id, m.dia)
    m.conta_id,
    m.dia,
    m.saldo_reportado
  from private.movimento_saldo_conta m
  cross join limites l
  where m.saldo_reportado is not null
    and m.dia >= l.inicio
    and m.dia <= l.fim
  order by
    m.conta_id,
    m.dia,
    m.momento desc,
    m.adaptador desc,
    m.movimento_id desc
), grade as (
  select
    d.dia,
    c.conta_id,
    c.conta,
    c.saldo_metodo,
    c.saldo_base,
    coalesce(a.total, 0::numeric) as movimento_antes,
    coalesce(m.total, 0::numeric) as movimento_dia,
    r.saldo_reportado,
    count(r.saldo_reportado) over (
      partition by c.conta_id
      order by d.dia
      rows between unbounded preceding and current row
    ) as grupo_reportado
  from dias d
  cross join contas_caixa c
  left join movimentos_antes a on a.conta_id = c.conta_id
  left join movimentos_dia m
    on m.conta_id = c.conta_id and m.dia = d.dia
  left join reportado_dia r
    on r.conta_id = c.conta_id and r.dia = d.dia
), acumulada as (
  select
    g.*,
    sum(g.movimento_dia) over (
      partition by g.conta_id
      order by g.dia
      rows between unbounded preceding and current row
    ) as movimento_acumulado,
    max(g.saldo_reportado) over (
      partition by g.conta_id, g.grupo_reportado
    ) as ultimo_saldo_reportado
  from grade g
)
select
  a.dia,
  a.conta_id,
  a.conta,
  round(
    case
      when a.saldo_metodo = 'extrato'
        then coalesce(
          a.ultimo_saldo_reportado,
          a.saldo_base + a.movimento_antes + a.movimento_acumulado
        )
      else a.saldo_base + a.movimento_antes + a.movimento_acumulado
    end,
    2
  ) as saldo
from acumulada a
order by a.dia, a.conta_id
with data;

create unique index if not exists mv_saldo_conta_diario_dia_conta_idx
  on private.mv_saldo_conta_diario (dia, conta_id);
create index if not exists mv_saldo_conta_diario_conta_dia_idx
  on private.mv_saldo_conta_diario (conta_id, dia);

revoke all privileges on table private.mv_saldo_conta_diario
  from public, anon, authenticated;

comment on materialized view private.mv_saldo_conta_diario is
  'Snapshot compacto de saldo diário por conta ativa configurada para compor o caixa.';

create or replace view private.saldo_caixa_diario as
with conta_especie as (
  select f.conta_id
  from public.fonte_financeira f
  where f.ativa
    and f.entra_caixa
    and f.saldo_adaptador = 'venda_especie'
  limit 1
), variacao_especie as (
  select m.dia, sum(m.valor) as valor
  from private.movimento_saldo_conta m
  where m.adaptador = 'venda_especie'
  group by m.dia
)
select
  s.dia,
  round(sum(s.saldo), 2) as saldo_total,
  round(
    coalesce(sum(s.saldo) filter (
      where s.conta_id = (select e.conta_id from conta_especie e)
    ), 0::numeric),
    2
  ) as dinheiro_pendente,
  round(coalesce(v.valor, 0::numeric), 2) as variacao_dinheiro_pendente
from private.mv_saldo_conta_diario s
left join variacao_especie v on v.dia = s.dia
group by s.dia, v.valor
order by s.dia;

revoke all privileges on table private.saldo_caixa_diario
  from public, anon, authenticated;

comment on view private.saldo_caixa_diario is
  'Total diário do caixa e componente de dinheiro físico derivados das contas configuradas.';

-- Traduz o novo formato para o contrato legado apenas durante a conferência.
-- Se uma única data mudar, a migration para aqui e nenhum consumidor é trocado.
do $equivalencia$
begin
  if position(
    'private.saldo_caixa_diario'
    in pg_get_functiondef('public.listar_calendario_financeiro(date)'::regprocedure)
  ) = 0 and exists (
    with ids as (
      select
        max(f.conta_id) filter (where f.saldo_adaptador = 'stone_extrato') as stone,
        max(f.conta_id) filter (where f.saldo_adaptador = 'bb') as bb,
        max(f.conta_id) filter (where f.saldo_adaptador = 'inter') as inter
      from public.fonte_financeira f
      where f.ativa and f.entra_caixa
    ), novo as (
      select
        t.dia,
        coalesce((
          select s.saldo
            from private.mv_saldo_conta_diario s
           where s.dia = t.dia and s.conta_id = ids.stone
        ), 0::numeric) as saldo_stone,
        coalesce((
          select s.saldo
            from private.mv_saldo_conta_diario s
           where s.dia = t.dia and s.conta_id = ids.bb
        ), 0::numeric) as saldo_bb,
        coalesce((
          select s.saldo
            from private.mv_saldo_conta_diario s
           where s.dia = t.dia and s.conta_id = ids.inter
        ), 0::numeric) as saldo_inter,
        t.dinheiro_pendente,
        t.variacao_dinheiro_pendente,
        t.saldo_total
      from private.saldo_caixa_diario t
      cross join ids
    ), diferenca as (
      (select * from pg_temp.saldo_generico_antes except all select * from novo)
      union all
      (select * from novo except all select * from pg_temp.saldo_generico_antes)
    )
    select 1 from diferenca limit 1
  ) then
    raise exception
      'Novo saldo por conta divergiu do snapshot anterior; conversão cancelada.';
  end if;
end;
$equivalencia$;

-- Mantém a assinatura histórica de saldo_anchor para não quebrar cálculos ou
-- clientes antigos. Stone/BB são campos de compatibilidade resolvidos pelo
-- adaptador; saldo_total já soma qualquer conta configurada.
create or replace view public.saldo_anchor as
with corte as (
  select c.dia
    from public.corte_caixa c
   limit 1
), ids as (
  select
    max(f.conta_id) filter (where f.ativa and f.entra_caixa and f.saldo_adaptador = 'stone_extrato') as stone,
    max(f.conta_id) filter (where f.ativa and f.entra_caixa and f.saldo_adaptador = 'bb') as bb
  from public.fonte_financeira f
)
select
  c.dia as data_ref,
  round(coalesce((
    select s.saldo
      from private.mv_saldo_conta_diario s
     where s.dia = c.dia and s.conta_id = i.stone
  ), 0::numeric), 2) as saldo_stone,
  round(coalesce((
    select s.saldo
      from private.mv_saldo_conta_diario s
     where s.dia = c.dia and s.conta_id = i.bb
  ), 0::numeric), 2) as saldo_bb,
  round(coalesce((
    select s.saldo_total
      from private.saldo_caixa_diario s
     where s.dia = c.dia
  ), 0::numeric), 2) as saldo_total,
  round(coalesce((
    select s.dinheiro_pendente
      from private.saldo_caixa_diario s
     where s.dia = c.dia
  ), 0::numeric), 2) as dinheiro_pendente
from corte c
cross join ids i;

comment on view public.saldo_anchor is
  'Âncora do caixa somando as contas ativas configuradas; campos Stone/BB são compatibilidade transitória.';

do $equivalencia_anchor$
begin
  if position(
    'private.mv_saldo_conta_diario'
    in pg_get_viewdef('public.saldo_anchor'::regclass, true)
  ) = 0 and exists (
    with diferenca as (
      (select * from pg_temp.saldo_anchor_antes except all select * from public.saldo_anchor)
      union all
      (select * from public.saldo_anchor except all select * from pg_temp.saldo_anchor_antes)
    )
    select 1 from diferenca limit 1
  ) then
    raise exception
      'Nova âncora de saldo divergiu do valor anterior; conversão cancelada.';
  end if;
end;
$equivalencia_anchor$;

create or replace view public.painel_saldo_por_conta as
select
  c.nome as conta,
  s.saldo,
  s.dia as data_ref
from private.mv_saldo_conta_diario s
join public.conta c on c.id = s.conta_id
cross join public.corte_caixa ct
where s.dia = ct.dia
  and s.saldo <> 0
order by c.nome;

comment on view public.painel_saldo_por_conta is
  'Distribuição do caixa por conta configurada, sem lista fixa de bancos.';

-- Migra automaticamente toda view que ainda dependia diretamente do snapshot
-- fixo. As opções de segurança existentes são preservadas.
do $migrar_views$
declare
  v record;
  v_definicao text;
  v_nova text;
  v_opcoes text;
begin
  for v in
    select distinct
      n.nspname as esquema,
      c.relname as nome,
      c.oid as oid,
      c.reloptions
    from pg_depend d
    join pg_rewrite r on r.oid = d.objid
    join pg_class c on c.oid = r.ev_class
    join pg_namespace n on n.oid = c.relnamespace
    where d.refobjid = 'public.mv_saldo_caixa_diario_detalhado'::regclass
      and c.relkind = 'v'
  loop
    v_definicao := pg_get_viewdef(v.oid, true);
    v_nova := replace(
      replace(
        v_definicao,
        'public.mv_saldo_caixa_diario_detalhado',
        'private.saldo_caixa_diario'
      ),
      'mv_saldo_caixa_diario_detalhado',
      'private.saldo_caixa_diario'
    );

    if v_nova = v_definicao then
      raise exception 'Não foi possível migrar a dependência de %.%.',
        v.esquema, v.nome;
    end if;

    v_opcoes := case
      when v.reloptions is null then ''
      else ' with (' || array_to_string(v.reloptions, ', ') || ')'
    end;

    execute format(
      'create or replace view %I.%I%s as %s',
      v.esquema,
      v.nome,
      v_opcoes,
      v_nova
    );
  end loop;
end;
$migrar_views$;

-- Funções PL/pgSQL não registram dependência da relação consultada; por isso
-- a troca é explícita e exige a quantidade esperada de ocorrências.
do $migrar_funcoes$
declare
  v_funcao regprocedure;
  v_esperadas integer;
  v_definicao text;
  v_nova text;
  v_ocorrencias integer;
  v_antiga constant text := 'public.mv_saldo_caixa_diario_detalhado';
  v_nova_relacao constant text := 'private.saldo_caixa_diario';
begin
  for v_funcao, v_esperadas in
    select 'public.listar_calendario_financeiro(date)'::regprocedure, 2
    union all
    select 'public.listar_despesas_dia(date)'::regprocedure, 1
  loop
    v_definicao := pg_get_functiondef(v_funcao);
    v_ocorrencias := (
      length(v_definicao) - length(replace(v_definicao, v_antiga, ''))
    ) / length(v_antiga);

    if v_ocorrencias = 0 and (
      (length(v_definicao) - length(replace(v_definicao, v_nova_relacao, '')))
      / length(v_nova_relacao)
    ) = v_esperadas then
      continue;
    end if;

    if v_ocorrencias <> v_esperadas then
      raise exception
        'Dependência de saldo inesperada em %: esperado %, encontrado %.',
        v_funcao, v_esperadas, v_ocorrencias;
    end if;

    v_nova := replace(
      v_definicao,
      v_antiga,
      v_nova_relacao
    );
    execute v_nova;
  end loop;
end;
$migrar_funcoes$;

create or replace function public.detalhar_saldo_caixa_dia(p_dia date)
returns table (
  dia date,
  saldo_stone numeric,
  saldo_bb numeric,
  saldo_inter numeric,
  dinheiro_pendente numeric,
  saldo_total numeric
)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso não autorizado.';
  end if;
  if p_dia is null then
    raise exception using errcode = '22023', message = 'Dia inválido.';
  end if;

  return query
  with ids as (
    select
      max(f.conta_id) filter (where f.ativa and f.entra_caixa and f.saldo_adaptador = 'stone_extrato') as stone,
      max(f.conta_id) filter (where f.ativa and f.entra_caixa and f.saldo_adaptador = 'bb') as bb,
      max(f.conta_id) filter (where f.ativa and f.entra_caixa and f.saldo_adaptador = 'inter') as inter
    from public.fonte_financeira f
  )
  select
    s.dia,
    coalesce((select m.saldo from private.mv_saldo_conta_diario m where m.dia = s.dia and m.conta_id = i.stone), 0::numeric),
    coalesce((select m.saldo from private.mv_saldo_conta_diario m where m.dia = s.dia and m.conta_id = i.bb), 0::numeric),
    coalesce((select m.saldo from private.mv_saldo_conta_diario m where m.dia = s.dia and m.conta_id = i.inter), 0::numeric),
    s.dinheiro_pendente,
    s.saldo_total
  from private.saldo_caixa_diario s
  cross join ids i
  where s.dia = p_dia;
end;
$function$;

revoke all privileges on function public.detalhar_saldo_caixa_dia(date)
  from public, anon, authenticated;
grant execute on function public.detalhar_saldo_caixa_dia(date)
  to authenticated;

create or replace function public.listar_saldo_contas_dia(p_dia date)
returns table (
  conta_id smallint,
  conta text,
  saldo numeric,
  saldo_total numeric
)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso não autorizado.';
  end if;
  if p_dia is null then
    raise exception using errcode = '22023', message = 'Dia inválido.';
  end if;

  return query
  select
    s.conta_id,
    c.nome,
    s.saldo,
    t.saldo_total
  from private.mv_saldo_conta_diario s
  join public.conta c on c.id = s.conta_id
  join private.saldo_caixa_diario t on t.dia = s.dia
  where s.dia = p_dia
  order by c.nome, s.conta_id;
end;
$function$;

revoke all privileges on function public.listar_saldo_contas_dia(date)
  from public, anon, authenticated;
grant execute on function public.listar_saldo_contas_dia(date)
  to authenticated;

create or replace function private.validar_configuracao_saldo()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  if exists (
    select 1
    from public.fonte_financeira f
    left join public.conta c on c.id = f.conta_id
    where f.ativa
      and f.entra_caixa
      and (
        f.saldo_adaptador = 'nenhum'
        or f.conta_id is null
        or not coalesce(c.ativa, false)
        or coalesce(c.saldo_metodo, 'ignorar') = 'ignorar'
      )
  ) then
    raise exception
      'Toda fonte ativa do caixa precisa de adaptador e conta ativa com cálculo de saldo.';
  end if;
end;
$function$;

revoke all privileges on function private.validar_configuracao_saldo()
  from public, anon, authenticated;

create or replace function private.validar_saldo_diario_materializado()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_corte date;
  v_maximo date;
begin
  perform private.validar_configuracao_saldo();

  select c.dia into v_corte from public.corte_caixa c limit 1;
  select max(s.dia) into v_maximo from private.mv_saldo_conta_diario s;

  if exists (
    select 1 from public.fonte_financeira f
    where f.ativa and f.entra_caixa and f.saldo_adaptador <> 'nenhum'
  ) and v_corte is not null and v_maximo is distinct from v_corte then
    raise exception
      'Snapshot de saldo por conta termina em %, corte_caixa é %.',
      v_maximo, v_corte;
  end if;

  if v_corte is not null and exists (
    with contas_caixa as (
      select distinct
        c.id as conta_id,
        c.saldo_metodo,
        c.saldo_data_base,
        c.saldo_base
      from public.conta c
      join public.fonte_financeira f on f.conta_id = c.id
      where c.ativa
        and c.saldo_metodo <> 'ignorar'
        and f.ativa
        and f.entra_caixa
        and f.saldo_adaptador <> 'nenhum'
    ), esperado as (
      select
        c.conta_id,
        round(
          case
            when c.saldo_metodo = 'extrato' then coalesce(
              (
                select m.saldo_reportado
                from private.movimento_saldo_conta m
                where m.conta_id = c.conta_id
                  and m.dia <= v_corte
                  and m.saldo_reportado is not null
                order by
                  m.dia desc,
                  m.momento desc,
                  m.adaptador desc,
                  m.movimento_id desc
                limit 1
              ),
              c.saldo_base + coalesce((
                select sum(m.valor)
                from private.movimento_saldo_conta m
                where m.conta_id = c.conta_id
                  and m.dia > c.saldo_data_base
                  and m.dia <= v_corte
              ), 0::numeric)
            )
            else c.saldo_base + coalesce((
              select sum(m.valor)
              from private.movimento_saldo_conta m
              where m.conta_id = c.conta_id
                and m.dia > c.saldo_data_base
                and m.dia <= v_corte
            ), 0::numeric)
          end,
          2
        ) as saldo
      from contas_caixa c
    ), obtido as (
      select s.conta_id, s.saldo
      from private.mv_saldo_conta_diario s
      where s.dia = v_corte
    ), diferenca as (
      (select * from esperado except all select * from obtido)
      union all
      (select * from obtido except all select * from esperado)
    )
    select 1 from diferenca limit 1
  ) then
    raise exception 'Snapshot do corte divergiu das fontes de saldo.';
  end if;

  if exists (
    select 1
    from private.saldo_caixa_diario s
    where s.saldo_total is distinct from (
      select round(sum(c.saldo), 2)
      from private.mv_saldo_conta_diario c
      where c.dia = s.dia
    )
  ) then
    raise exception 'Total diário não fecha com os saldos das contas.';
  end if;

  if v_corte is not null and exists (
    select 1
    from private.saldo_caixa_diario s
    cross join public.saldo_anchor a
    where s.dia = v_corte
      and (
        s.saldo_total is distinct from a.saldo_total
        or s.dinheiro_pendente is distinct from a.dinheiro_pendente
      )
  ) then
    raise exception 'Snapshot do corte divergiu de saldo_anchor.';
  end if;
end;
$function$;

revoke all privileges on function private.validar_saldo_diario_materializado()
  from public, anon, authenticated;

-- Salvar uma conta passa a incluir sua regra de saldo. A RPC antiga continua
-- disponível até todos os navegadores receberem o HTML novo.
create or replace function public.admin_salvar_conta_com_saldo(
  p_id smallint,
  p_nome text,
  p_banco text,
  p_unidade_id smallint,
  p_ativa boolean,
  p_saldo_metodo text,
  p_saldo_data_base date,
  p_saldo_base numeric
)
returns public.conta
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v public.conta;
  v_anterior public.conta;
  v_unidade_id smallint;
  v_metodo text := coalesce(nullif(btrim(p_saldo_metodo), ''), 'ignorar');
  v_data_base date := coalesce(p_saldo_data_base, date '0001-01-01');
  v_dia date;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;

  select c.unidade_principal_id into v_unidade_id
  from public.configuracao_operacional c
  where c.singleton;

  if btrim(coalesce(p_nome, '')) = '' then
    raise exception using errcode = '22023', message = 'Nome obrigatório.';
  end if;
  if p_unidade_id is not null and p_unidade_id <> v_unidade_id then
    raise exception using errcode = '22023',
      message = 'A conta deve pertencer à unidade principal.';
  end if;
  if v_metodo <> all (array['ignorar', 'extrato', 'movimentos']::text[]) then
    raise exception using errcode = '22023', message = 'Método de saldo inválido.';
  end if;
  if p_saldo_base is null
     or p_saldo_base::text = any (array['NaN', 'Infinity', '-Infinity']::text[]) then
    raise exception using errcode = '22023', message = 'Saldo-base inválido.';
  end if;
  if p_id is not null and exists (
    select 1
    from public.fonte_financeira f
    where f.conta_id = p_id and f.ativa and f.entra_caixa
  ) and (not coalesce(p_ativa, true) or v_metodo = 'ignorar') then
    raise exception using errcode = '22023',
      message = 'Uma conta usada por fonte ativa do caixa não pode ser desativada ou ignorada.';
  end if;

  if p_id is null then
    insert into public.conta (
      nome, banco, unidade_id, ativa,
      saldo_metodo, saldo_data_base, saldo_base
    ) values (
      btrim(p_nome), nullif(btrim(p_banco), ''), v_unidade_id,
      coalesce(p_ativa, true), v_metodo, v_data_base, p_saldo_base
    )
    returning * into v;
  else
    select * into v_anterior
    from public.conta c
    where c.id = p_id
    for update;

    if not found then
      raise exception using errcode = '22023', message = 'Conta id desconhecido.';
    end if;

    update public.conta c
       set nome = btrim(p_nome),
           banco = nullif(btrim(p_banco), ''),
           unidade_id = v_unidade_id,
           ativa = coalesce(p_ativa, true),
           saldo_metodo = v_metodo,
           saldo_data_base = v_data_base,
           saldo_base = p_saldo_base
     where c.id = p_id
     returning * into v;
  end if;

  -- Conserva a tabela antiga sincronizada enquanto o snapshot legado existir.
  insert into public.saldo_inicial (conta, data_base, saldo, obs)
  select f.chave, v.saldo_data_base, v.saldo_base,
         'Sincronizado pelo cadastro da conta'
  from public.fonte_financeira f
  where f.conta_id = v.id and f.saldo_adaptador = 'bb'
  on conflict (conta) do update
    set data_base = excluded.data_base,
        saldo = excluded.saldo;

  if p_id is null or to_jsonb(v_anterior) is distinct from to_jsonb(v) then
    select coalesce(c.dia, current_date) into v_dia
    from public.corte_caixa c
    limit 1;
    perform private.agendar_refresh_painel(
      coalesce(v_dia, current_date),
      coalesce(v_dia, current_date)
    );
  end if;

  return v;
end;
$function$;

revoke all privileges on function public.admin_salvar_conta_com_saldo(
  smallint, text, text, smallint, boolean, text, date, numeric
) from public, anon, authenticated;
grant execute on function public.admin_salvar_conta_com_saldo(
  smallint, text, text, smallint, boolean, text, date, numeric
) to authenticated;

create or replace function public.admin_salvar_conta(
  p_id smallint,
  p_nome text,
  p_banco text,
  p_unidade_id smallint,
  p_ativa boolean
)
returns public.conta
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_atual public.conta;
begin
  if p_id is not null then
    select * into v_atual from public.conta c where c.id = p_id;
  end if;

  return public.admin_salvar_conta_com_saldo(
    p_id,
    p_nome,
    p_banco,
    p_unidade_id,
    p_ativa,
    coalesce(v_atual.saldo_metodo, 'ignorar'),
    coalesce(v_atual.saldo_data_base, date '0001-01-01'),
    coalesce(v_atual.saldo_base, 0::numeric)
  );
end;
$function$;

-- A nova RPC expõe o adaptador; a assinatura antiga preserva o valor atual.
create or replace function public.admin_salvar_fonte_financeira_com_saldo(
  p_chave text,
  p_nome text,
  p_conta_id smallint,
  p_ativa boolean,
  p_entra_faturamento boolean,
  p_entra_caixa boolean,
  p_entra_caixa_historico boolean,
  p_entra_dre boolean,
  p_saldo_adaptador text
)
returns public.fonte_financeira
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_anterior public.fonte_financeira;
  v public.fonte_financeira;
  v_adaptador text := coalesce(nullif(btrim(p_saldo_adaptador), ''), 'nenhum');
  v_dia date;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  if btrim(coalesce(p_nome, '')) = '' then
    raise exception using errcode = '22023', message = 'Nome da fonte obrigatório.';
  end if;
  if v_adaptador <> all (
    array['nenhum', 'stone_extrato', 'bb', 'inter', 'bs_cash', 'venda_especie']::text[]
  ) then
    raise exception using errcode = '22023', message = 'Adaptador de saldo inválido.';
  end if;

  select * into v_anterior
  from public.fonte_financeira f
  where f.chave = p_chave
  for update;

  if not found then
    raise exception using errcode = '22023', message = 'Fonte desconhecida.';
  end if;

  if p_conta_id is not null and not exists (
    select 1 from public.conta c where c.id = p_conta_id and c.ativa
  ) then
    raise exception using errcode = '22023',
      message = 'Conta padrão inválida ou inativa.';
  end if;

  if coalesce(p_ativa, true) and coalesce(p_entra_caixa, false) then
    if p_conta_id is null or v_adaptador = 'nenhum' then
      raise exception using errcode = '22023',
        message = 'Fonte ativa do caixa exige conta e adaptador de saldo.';
    end if;
    if not exists (
      select 1
      from public.conta c
      where c.id = p_conta_id
        and c.ativa
        and c.saldo_metodo <> 'ignorar'
    ) then
      raise exception using errcode = '22023',
        message = 'A conta escolhida precisa ter cálculo de saldo ativo.';
    end if;
    if exists (
      select 1
      from public.fonte_financeira f
      where f.chave <> p_chave
        and f.ativa
        and f.entra_caixa
        and f.saldo_adaptador = v_adaptador
    ) then
      raise exception using errcode = '22023',
        message = 'Este adaptador já alimenta outra fonte ativa do caixa.';
    end if;
  end if;

  update public.fonte_financeira f
     set nome = btrim(p_nome),
         conta_id = p_conta_id,
         ativa = coalesce(p_ativa, true),
         entra_faturamento = coalesce(p_entra_faturamento, false),
         entra_caixa = coalesce(p_entra_caixa, false),
         entra_caixa_historico = coalesce(p_entra_caixa_historico, false),
         entra_dre = coalesce(p_entra_dre, false),
         saldo_adaptador = v_adaptador,
         atualizado_por = auth.uid(),
         atualizado_em = now()
   where f.chave = p_chave
   returning * into v;

  perform private.validar_configuracao_saldo();

  if to_jsonb(v_anterior) is distinct from to_jsonb(v) then
    insert into private.fonte_financeira_historico (
      chave, configuracao_anterior, configuracao_nova, alterado_por
    ) values (
      v.chave, to_jsonb(v_anterior), to_jsonb(v), auth.uid()
    );

    select coalesce(c.dia, current_date) into v_dia
    from public.corte_caixa c
    limit 1;
    perform private.agendar_refresh_painel(
      coalesce(v_dia, current_date),
      coalesce(v_dia, current_date)
    );
  end if;

  return v;
end;
$function$;

revoke all privileges on function public.admin_salvar_fonte_financeira_com_saldo(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text
) from public, anon, authenticated;
grant execute on function public.admin_salvar_fonte_financeira_com_saldo(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text
) to authenticated;

create or replace function public.admin_salvar_fonte_financeira(
  p_chave text,
  p_nome text,
  p_conta_id smallint,
  p_ativa boolean,
  p_entra_faturamento boolean,
  p_entra_caixa boolean,
  p_entra_caixa_historico boolean,
  p_entra_dre boolean
)
returns public.fonte_financeira
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_adaptador text;
begin
  select f.saldo_adaptador into v_adaptador
  from public.fonte_financeira f
  where f.chave = p_chave;

  return public.admin_salvar_fonte_financeira_com_saldo(
    p_chave,
    p_nome,
    p_conta_id,
    p_ativa,
    p_entra_faturamento,
    p_entra_caixa,
    p_entra_caixa_historico,
    p_entra_dre,
    coalesce(v_adaptador, 'nenhum')
  );
end;
$function$;

create or replace function public.admin_salvar_saldo_inicial(
  p_conta text,
  p_data_base date,
  p_saldo numeric,
  p_obs text
)
returns public.saldo_inicial
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v public.saldo_inicial;
  v_dia date;
begin
  perform public.exigir_admin();
  if btrim(coalesce(p_conta, '')) = ''
     or p_data_base is null
     or p_saldo is null then
    raise exception using errcode = '22023',
      message = 'Conta, data-base e saldo são obrigatórios.';
  end if;

  insert into public.saldo_inicial (conta, data_base, saldo, obs)
  values (btrim(p_conta), p_data_base, p_saldo, p_obs)
  on conflict (conta) do update
    set data_base = excluded.data_base,
        saldo = excluded.saldo,
        obs = excluded.obs
  returning * into v;

  update public.conta c
     set saldo_data_base = p_data_base,
         saldo_base = p_saldo
    from public.fonte_financeira f
   where f.conta_id = c.id
     and lower(f.chave) = lower(btrim(p_conta));

  select coalesce(c.dia, current_date) into v_dia
  from public.corte_caixa c
  limit 1;
  perform private.agendar_refresh_painel(
    coalesce(v_dia, current_date),
    coalesce(v_dia, current_date)
  );

  return v;
end;
$function$;

-- O worker pequeno das sangrias mantém o nome por compatibilidade, mas agora
-- atualiza somente o snapshot genérico usado pelas telas.
create or replace function private.refresh_saldo_caixa_diario_detalhado()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  set local statement_timeout = 0;
  refresh materialized view concurrently private.mv_saldo_conta_diario;
  perform private.validar_saldo_diario_materializado();
end;
$function$;

revoke all privileges on function private.refresh_saldo_caixa_diario_detalhado()
  from public, anon, authenticated;

-- Primeiro atualiza a âncora de saldo; depois, os derivados que a consomem.
-- O snapshot fixo antigo deixa de ser recalculado e permanece apenas como
-- contingência reversível desta implantação.
create or replace function public.refresh_painel()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  set local statement_timeout = 0;
  refresh materialized view concurrently private.mv_saldo_conta_diario;
  refresh materialized view concurrently public.mv_fluxo_caixa_diario;
  refresh materialized view concurrently public.mv_despesa_mensal;
  refresh materialized view concurrently public.mv_despesa_diaria;
  refresh materialized view concurrently public.mv_conciliacao_contabil;

  perform private.validar_saldo_diario_materializado();
  perform private.validar_fluxo_materializado();
  perform private.validar_despesas_materializadas();
end;
$function$;

create or replace function private.processar_virada_financeira()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_corte date;
  v_snapshot date;
begin
  if not pg_try_advisory_xact_lock(18110000::bigint) then
    return;
  end if;

  select c.dia into v_corte from public.corte_caixa c limit 1;
  select max(s.dia) into v_snapshot
    from private.mv_saldo_conta_diario s;

  if v_corte is null or v_snapshot is not distinct from v_corte then
    return;
  end if;

  set local statement_timeout = 0;
  refresh materialized view concurrently private.mv_saldo_conta_diario;
  refresh materialized view concurrently public.mv_fluxo_caixa_diario;
  perform private.validar_saldo_diario_materializado();
  perform private.validar_fluxo_materializado();
end;
$function$;

revoke all privileges on function private.processar_virada_financeira()
  from public, anon, authenticated;

comment on function private.validar_configuracao_saldo() is
  'Impede fonte ativa do caixa sem adaptador ou sem conta apta a calcular saldo.';
comment on function private.validar_saldo_diario_materializado() is
  'Compara o fechamento materializado de cada conta com seus movimentos ou último saldo reportado.';
comment on function private.refresh_saldo_caixa_diario_detalhado() is
  'Atualização assíncrona e pequena do saldo por conta após alteração de sangria.';
comment on function private.processar_virada_financeira() is
  'Atualiza saldo por conta e fluxo somente quando o corte diário avançar.';
comment on function public.listar_saldo_contas_dia(date) is
  'Detalha dinamicamente as contas que formam o saldo de um dia do Calendário.';

-- O refresh final é também um teste em dados reais dentro da transação. Se
-- qualquer MV ou conta não fechar, tudo acima é revertido.
select public.refresh_painel();

do $contratos$
declare
  v_calendario text := lower(pg_get_functiondef(
    'public.listar_calendario_financeiro(date)'::regprocedure
  ));
  v_despesas text := lower(pg_get_functiondef(
    'public.listar_despesas_dia(date)'::regprocedure
  ));
  v_refresh text := lower(pg_get_functiondef(
    'public.refresh_painel()'::regprocedure
  ));
  v_virada text := lower(pg_get_functiondef(
    'private.processar_virada_financeira()'::regprocedure
  ));
begin
  if position('least(p_mes, coalesce(ct.caixa, p_mes) + 1)' in v_calendario) = 0
     or position('cfg_fonte.entra_caixa' in v_calendario) = 0
     or position('cfg_historica.entra_caixa_historico' in v_calendario) = 0
     or position('private.saldo_caixa_diario' in v_calendario) = 0
     or position('cfg_fonte.entra_caixa' in v_despesas) = 0
     or position('cfg_historica.entra_caixa_historico' in v_despesas) = 0
     or position('private.saldo_caixa_diario' in v_despesas) = 0 then
    raise exception 'Contrato efetivo do Calendário ficou incompleto.';
  end if;

  if position('private.mv_saldo_conta_diario' in v_refresh) = 0
     or position('private.mv_saldo_conta_diario' in v_virada) = 0
     or position('mv_saldo_caixa_diario_detalhado' in v_refresh) > 0
     or position('mv_saldo_caixa_diario_detalhado' in v_virada) > 0 then
    raise exception 'Rotina efetiva de atualização ainda usa o saldo fixo.';
  end if;

  if exists (
    select 1
    from pg_depend d
    join pg_rewrite r on r.oid = d.objid
    join pg_class c on c.oid = r.ev_class
    where d.refobjid = 'public.mv_saldo_caixa_diario_detalhado'::regclass
      and c.relkind = 'v'
  ) then
    raise exception 'Uma view de produção ainda depende do saldo fixo.';
  end if;
end;
$contratos$;

commit;
