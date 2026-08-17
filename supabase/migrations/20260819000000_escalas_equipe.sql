-- Rotina "Escalas": cadastro da equipe, jornada semanal por pessoa e a curva
-- de demanda que serve de regua para dimensionar cada turno.
--
-- A curva vem de recebimento_transacao_net deslocada pela defasagem entre a
-- hora do pedido e a hora do pagamento. O pagamento acontece no fim da
-- refeicao; o trabalho de salao e cozinha aconteceu antes. Sem esse
-- deslocamento a escala seria dimensionada com mais de uma hora de atraso.
-- A defasagem foi estimada em 75 min cruzando a curva de lancamento do
-- sistema de vendas com a curva de pagamento deste banco, e fica configuravel
-- em escala_config para poder ser recalibrada.
--
-- Horarios sao guardados em MINUTOS desde a meia-noite do dia da escala, e nao
-- como `time`. Assim um turno que fecha 00:40 e simplesmente 1240, sem virada
-- de data: se o horario ao publico de sexta/sabado for esticado, o fechamento
-- da cozinha passa da meia-noite e continua cabendo no mesmo modelo.
--
-- Nenhum nome de funcionario e versionado aqui: o cadastro e feito pela
-- propria pagina.

begin;

-- ---------------------------------------------------------------------------
-- Configuracao
-- ---------------------------------------------------------------------------

create table if not exists public.escala_config (
  chave text primary key,
  valor numeric not null,
  descricao text not null
);

insert into public.escala_config (chave, valor, descricao) values
  ('defasagem_venda_pagamento_min', 75,
   'Minutos entre o pedido e o pagamento. Desloca a curva para o horario em que o trabalho acontece.'),
  ('capacidade_vendas_hora_pessoa', 4.18,
   'Teto de vendas/hora que uma pessoa atende. Calibrado pelo pico atual (domingo 17h com 3 pessoas).'),
  ('carga_semanal_horas', 44,
   'Jornada semanal contratual. A diferenca para a escala montada vira banco de horas.'),
  ('margem_intervalo_min', 90,
   'Distancia minima entre o intervalo e as pontas da jornada. A CLT nao fixa numero, mas o TST trata como supressao o intervalo concedido no inicio ou no fim da jornada.'),
  ('meses_historico', 12,
   'Janela de historico usada para montar a curva de demanda.')
on conflict (chave) do update
  set descricao = excluded.descricao;

comment on table public.escala_config is
  'Parametros da rotina de escalas. Alterar aqui muda a regua de toda a pagina.';

-- ---------------------------------------------------------------------------
-- Funcionamento da casa por dia da semana
-- ---------------------------------------------------------------------------

create table if not exists public.escala_funcionamento (
  dia_semana smallint primary key check (dia_semana between 1 and 7),
  abertura_min smallint not null check (abertura_min between 0 and 1439),
  fechamento_min smallint not null check (fechamento_min between 1 and 1800),
  pre_abertura_min smallint not null default 30 check (pre_abertura_min between 0 and 180),
  pos_fechamento_min smallint not null default 30 check (pos_fechamento_min between 0 and 180),
  check (fechamento_min > abertura_min)
);

comment on table public.escala_funcionamento is
  'Horario ao publico por dia da semana, mais o tempo de producao antes de abrir e de encerramento depois de fechar.';

-- Foto de hoje: dom-qui 09:00-22:15, sex-sab 09:00-23:00. Sex/sab/dom/seg
-- produzem e encerram mais que ter/qua/qui.
insert into public.escala_funcionamento
  (dia_semana, abertura_min, fechamento_min, pre_abertura_min, pos_fechamento_min) values
  (1, 540, 1335, 40, 40),
  (2, 540, 1335, 30, 20),
  (3, 540, 1335, 30, 20),
  (4, 540, 1335, 30, 20),
  (5, 540, 1380, 40, 40),
  (6, 540, 1380, 40, 40),
  (7, 540, 1335, 40, 40)
on conflict (dia_semana) do nothing;

-- ---------------------------------------------------------------------------
-- Equipe
-- ---------------------------------------------------------------------------

create table if not exists public.escala_funcionario (
  id bigint generated always as identity primary key,
  nome text not null check (length(btrim(nome)) between 2 and 120),
  equipe text not null check (equipe in ('salao', 'cozinha')),
  funcao text not null check (funcao in (
    'gerente_salao', 'garcom', 'lider_cozinha', 'cozinha'
  )),
  regime text not null default '5x2' check (regime in ('5x2', '6x1')),
  carga_semanal_horas numeric(5,2) not null default 44
    check (carga_semanal_horas between 20 and 44),
  autonomia_fechamento boolean not null default false,
  ativo boolean not null default true,
  ordem smallint not null default 100,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (nome)
);

comment on column public.escala_funcionario.autonomia_fechamento is
  'Pode encerrar a casa sozinho. Quem nao tem autonomia nunca deveria ficar escalado sozinho no fechamento.';

create table if not exists public.escala_turno (
  id bigint generated always as identity primary key,
  funcionario_id bigint not null
    references public.escala_funcionario(id) on delete cascade,
  dia_semana smallint not null check (dia_semana between 1 and 7),
  folga boolean not null default true,
  entrada_min smallint check (entrada_min between 0 and 1439),
  saida_min smallint check (saida_min between 1 and 1800),
  intervalo_inicio_min smallint check (intervalo_inicio_min between 0 and 1800),
  intervalo_fim_min smallint check (intervalo_fim_min between 1 and 1800),
  atualizado_por uuid references auth.users(id) on delete set null,
  atualizado_em timestamptz not null default now(),
  unique (funcionario_id, dia_semana),
  constraint escala_turno_folga_vazia check (
    not folga or (entrada_min is null and saida_min is null
      and intervalo_inicio_min is null and intervalo_fim_min is null)
  ),
  constraint escala_turno_jornada check (
    folga or (
      entrada_min is not null and saida_min is not null
      and saida_min > entrada_min
      and saida_min - entrada_min <= 780      -- teto de 13h de permanencia
    )
  ),
  constraint escala_turno_intervalo check (
    folga or intervalo_inicio_min is null or (
      intervalo_fim_min is not null
      and intervalo_fim_min > intervalo_inicio_min
      and intervalo_inicio_min > entrada_min
      and intervalo_fim_min < saida_min
    )
  )
);

comment on table public.escala_turno is
  'Jornada semanal por pessoa, em minutos desde a meia-noite. saida_min acima de 1440 significa fechamento depois da meia-noite.';

create index if not exists escala_turno_dia_idx
  on public.escala_turno (dia_semana, funcionario_id);
create index if not exists escala_funcionario_ordem_idx
  on public.escala_funcionario (ativo desc, equipe, ordem, nome);

alter table public.escala_config enable row level security;
alter table public.escala_funcionamento enable row level security;
alter table public.escala_funcionario enable row level security;
alter table public.escala_turno enable row level security;
revoke all privileges on public.escala_config from public, anon, authenticated;
revoke all privileges on public.escala_funcionamento from public, anon, authenticated;
revoke all privileges on public.escala_funcionario from public, anon, authenticated;
revoke all privileges on public.escala_turno from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Curva de demanda
-- ---------------------------------------------------------------------------

-- Desloca cada transacao para o horario provavel do pedido e agrega por dia da
-- semana e hora. Deslocar a transacao (e nao a curva ja agregada) mantem o
-- resultado exato quando a defasagem nao e multipla de uma hora.
create or replace view public.escala_demanda_base as
with cfg as (
  select
    coalesce((select valor from public.escala_config
              where chave = 'defasagem_venda_pagamento_min'), 75) as lag_min,
    coalesce((select valor from public.escala_config
              where chave = 'meses_historico'), 12) as meses
),
corte as (
  select
    (select max(data_venda)::date from public.recebimento_transacao_net) as fim,
    (select max(data_venda)::date from public.recebimento_transacao_net)
      - (cfg.meses * 30)::integer as inicio,
    cfg.lag_min
  from cfg
),
pedido as (
  select
    t.data_venda - make_interval(mins => corte.lag_min::integer) as momento,
    t.bruto_net
  from public.recebimento_transacao_net t, corte
  where t.data_venda >= corte.inicio and t.data_venda < corte.fim
),
dias as (
  select
    extract(isodow from momento)::smallint as dia_semana,
    count(distinct momento::date) as dias
  from pedido
  group by 1
)
select
  extract(isodow from p.momento)::smallint as dia_semana,
  extract(hour from p.momento)::smallint as hora,
  d.dias::integer as dias_observados,
  (count(*)::numeric / d.dias)::numeric(10,3) as vendas_hora,
  (sum(p.bruto_net) / d.dias)::numeric(12,2) as valor_hora
from pedido p
join dias d on d.dia_semana = extract(isodow from p.momento)::smallint
group by 1, 2, d.dias;

comment on view public.escala_demanda_base is
  'Curva de demanda por dia da semana e hora, no horario estimado do PEDIDO (nao do pagamento). Cobre ~94% do faturamento: a venda em especie nao tem hora.';

create or replace view public.app_escala_demanda
with (security_barrier = true, security_invoker = false) as
select
  b.dia_semana,
  b.hora,
  b.dias_observados,
  b.vendas_hora,
  b.valor_hora,
  ceil(b.vendas_hora / nullif(c.valor, 0))::smallint as pessoas_necessarias
from public.escala_demanda_base b
cross join (
  select valor from public.escala_config
  where chave = 'capacidade_vendas_hora_pessoa'
) c
where public.usuario_pode_acessar_alguma_pagina(array['escalas.html']::text[]);

-- Config e funcionamento tambem passam por view: as tabelas ficam sem grant
-- para authenticated, entao a pagina nao as le direto.
create or replace view public.app_escala_config
with (security_barrier = true, security_invoker = false) as
select c.chave, c.valor, c.descricao
from public.escala_config c
where public.usuario_pode_acessar_alguma_pagina(array['escalas.html']::text[]);

create or replace view public.app_escala_funcionamento
with (security_barrier = true, security_invoker = false) as
select
  f.dia_semana,
  f.abertura_min,
  f.fechamento_min,
  f.pre_abertura_min,
  f.pos_fechamento_min
from public.escala_funcionamento f
where public.usuario_pode_acessar_alguma_pagina(array['escalas.html']::text[]);

-- ---------------------------------------------------------------------------
-- Escala montada
-- ---------------------------------------------------------------------------

create or replace view public.escala_turno_base as
select
  f.id as funcionario_id,
  f.nome,
  f.equipe,
  f.funcao,
  f.regime,
  f.carga_semanal_horas,
  f.autonomia_fechamento,
  f.ativo,
  f.ordem,
  d.dia_semana,
  coalesce(t.folga, true) as folga,
  t.entrada_min,
  t.saida_min,
  t.intervalo_inicio_min,
  t.intervalo_fim_min,
  case
    when coalesce(t.folga, true) then 0
    else (t.saida_min - t.entrada_min
          - coalesce(t.intervalo_fim_min - t.intervalo_inicio_min, 0)) / 60.0
  end::numeric(6,3) as horas_trabalhadas,
  t.atualizado_em
from public.escala_funcionario f
cross join generate_series(1, 7) as d(dia_semana)
left join public.escala_turno t
  on t.funcionario_id = f.id and t.dia_semana = d.dia_semana;

create or replace view public.app_escala_turnos
with (security_barrier = true, security_invoker = false) as
select
  b.funcionario_id,
  b.nome,
  b.equipe,
  b.funcao,
  b.regime,
  b.carga_semanal_horas,
  b.autonomia_fechamento,
  b.ativo,
  b.ordem,
  b.dia_semana,
  b.folga,
  b.entrada_min,
  b.saida_min,
  b.intervalo_inicio_min,
  b.intervalo_fim_min,
  b.horas_trabalhadas,
  b.atualizado_em,
  sum(b.horas_trabalhadas) over (partition by b.funcionario_id)
    as horas_semana,
  (sum(b.horas_trabalhadas) over (partition by b.funcionario_id)
    - b.carga_semanal_horas)::numeric(6,3) as banco_horas_semana,
  count(*) filter (where b.folga) over (partition by b.funcionario_id)
    as folgas_semana
from public.escala_turno_base b
where public.usuario_pode_acessar_alguma_pagina(array['escalas.html']::text[]);

-- Cobertura hora a hora: quantas pessoas de cada equipe estao na casa e fora
-- do intervalo, contra o que a curva de demanda pede. A amostragem e no meio
-- da hora (minuto 30) para nao contar quem esta entrando ou saindo na virada.
create or replace view public.app_escala_cobertura
with (security_barrier = true, security_invoker = false) as
with grade as (
  select d.dia_semana, h.hora, h.hora * 60 + 30 as minuto
  from generate_series(1, 7) as d(dia_semana)
  cross join generate_series(0, 26) as h(hora)
),
equipes as (select unnest(array['salao', 'cozinha']) as equipe),
presente as (
  select
    g.dia_semana,
    g.hora,
    e.equipe,
    count(b.funcionario_id) filter (
      where not b.folga
        and b.entrada_min <= g.minuto
        and b.saida_min > g.minuto
        and (b.intervalo_inicio_min is null
             or g.minuto < b.intervalo_inicio_min
             or g.minuto >= b.intervalo_fim_min)
    )::smallint as pessoas
  from grade g
  cross join equipes e
  left join public.escala_turno_base b
    on b.dia_semana = g.dia_semana and b.ativo and b.equipe = e.equipe
  group by g.dia_semana, g.hora, e.equipe
)
select
  p.dia_semana,
  p.equipe,
  p.hora,
  p.pessoas,
  coalesce(dm.vendas_hora, 0) as vendas_hora,
  case when p.pessoas > 0
    then (coalesce(dm.vendas_hora, 0) / p.pessoas)::numeric(8,2)
  end as vendas_por_pessoa,
  f.abertura_min,
  f.fechamento_min,
  f.pre_abertura_min,
  f.pos_fechamento_min,
  (p.hora * 60 + 30) between (f.abertura_min - f.pre_abertura_min)
                         and (f.fechamento_min + f.pos_fechamento_min)
    as dentro_da_janela
from presente p
join public.escala_funcionamento f on f.dia_semana = p.dia_semana
left join public.escala_demanda_base dm
  on dm.dia_semana = p.dia_semana and dm.hora = (p.hora % 24)
where public.usuario_pode_acessar_alguma_pagina(array['escalas.html']::text[]);

-- ---------------------------------------------------------------------------
-- Escrita
-- ---------------------------------------------------------------------------

create or replace function public.salvar_escala_funcionario(
  p_id bigint,
  p_nome text,
  p_equipe text,
  p_funcao text,
  p_regime text default '5x2',
  p_carga numeric default 44,
  p_autonomia boolean default false,
  p_ativo boolean default true,
  p_ordem smallint default 100
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id bigint;
begin
  if not public.usuario_pode_acessar_alguma_pagina(array['escalas.html']::text[]) then
    raise exception 'Sem permissao para editar escalas.';
  end if;

  if p_id is null then
    insert into public.escala_funcionario
      (nome, equipe, funcao, regime, carga_semanal_horas, autonomia_fechamento,
       ativo, ordem, criado_por, atualizado_por)
    values (btrim(p_nome), p_equipe, p_funcao, p_regime, p_carga, p_autonomia,
            p_ativo, p_ordem, auth.uid(), auth.uid())
    returning id into v_id;

    insert into public.escala_turno (funcionario_id, dia_semana, folga, atualizado_por)
    select v_id, d, true, auth.uid() from generate_series(1, 7) as d;
  else
    update public.escala_funcionario set
      nome = btrim(p_nome),
      equipe = p_equipe,
      funcao = p_funcao,
      regime = p_regime,
      carga_semanal_horas = p_carga,
      autonomia_fechamento = p_autonomia,
      ativo = p_ativo,
      ordem = p_ordem,
      atualizado_por = auth.uid(),
      atualizado_em = now()
    where id = p_id
    returning id into v_id;

    if v_id is null then
      raise exception 'Funcionario % nao encontrado.', p_id;
    end if;
  end if;

  return v_id;
end;
$function$;

create or replace function public.salvar_escala_turno(
  p_funcionario_id bigint,
  p_dia_semana smallint,
  p_folga boolean,
  p_entrada_min smallint default null,
  p_saida_min smallint default null,
  p_intervalo_inicio_min smallint default null,
  p_intervalo_fim_min smallint default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_alguma_pagina(array['escalas.html']::text[]) then
    raise exception 'Sem permissao para editar escalas.';
  end if;

  insert into public.escala_turno
    (funcionario_id, dia_semana, folga, entrada_min, saida_min,
     intervalo_inicio_min, intervalo_fim_min, atualizado_por, atualizado_em)
  values (
    p_funcionario_id, p_dia_semana, p_folga,
    case when p_folga then null else p_entrada_min end,
    case when p_folga then null else p_saida_min end,
    case when p_folga then null else p_intervalo_inicio_min end,
    case when p_folga then null else p_intervalo_fim_min end,
    auth.uid(), now())
  on conflict (funcionario_id, dia_semana) do update set
    folga = excluded.folga,
    entrada_min = excluded.entrada_min,
    saida_min = excluded.saida_min,
    intervalo_inicio_min = excluded.intervalo_inicio_min,
    intervalo_fim_min = excluded.intervalo_fim_min,
    atualizado_por = excluded.atualizado_por,
    atualizado_em = now();
end;
$function$;

create or replace function public.excluir_escala_funcionario(p_id bigint)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_alguma_pagina(array['escalas.html']::text[]) then
    raise exception 'Sem permissao para editar escalas.';
  end if;
  delete from public.escala_funcionario where id = p_id;
end;
$function$;

create or replace function public.salvar_escala_funcionamento(
  p_dia_semana smallint,
  p_abertura_min smallint,
  p_fechamento_min smallint,
  p_pre_min smallint,
  p_pos_min smallint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_alguma_pagina(array['escalas.html']::text[]) then
    raise exception 'Sem permissao para editar escalas.';
  end if;

  insert into public.escala_funcionamento
    (dia_semana, abertura_min, fechamento_min, pre_abertura_min, pos_fechamento_min)
  values (p_dia_semana, p_abertura_min, p_fechamento_min, p_pre_min, p_pos_min)
  on conflict (dia_semana) do update set
    abertura_min = excluded.abertura_min,
    fechamento_min = excluded.fechamento_min,
    pre_abertura_min = excluded.pre_abertura_min,
    pos_fechamento_min = excluded.pos_fechamento_min;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Permissoes
-- ---------------------------------------------------------------------------

revoke all privileges on public.escala_demanda_base from public, anon, authenticated;
revoke all privileges on public.escala_turno_base from public, anon, authenticated;
revoke all privileges on public.app_escala_demanda from public, anon, authenticated;
revoke all privileges on public.app_escala_turnos from public, anon, authenticated;
revoke all privileges on public.app_escala_cobertura from public, anon, authenticated;
revoke all privileges on public.app_escala_config from public, anon, authenticated;
revoke all privileges on public.app_escala_funcionamento from public, anon, authenticated;
grant select on public.app_escala_demanda to authenticated;
grant select on public.app_escala_turnos to authenticated;
grant select on public.app_escala_cobertura to authenticated;
grant select on public.app_escala_config to authenticated;
grant select on public.app_escala_funcionamento to authenticated;

revoke all privileges on function public.salvar_escala_funcionario(bigint, text, text, text, text, numeric, boolean, boolean, smallint) from public, anon, authenticated;
revoke all privileges on function public.salvar_escala_turno(bigint, smallint, boolean, smallint, smallint, smallint, smallint) from public, anon, authenticated;
revoke all privileges on function public.excluir_escala_funcionario(bigint) from public, anon, authenticated;
revoke all privileges on function public.salvar_escala_funcionamento(smallint, smallint, smallint, smallint, smallint) from public, anon, authenticated;
grant execute on function public.salvar_escala_funcionario(bigint, text, text, text, text, numeric, boolean, boolean, smallint) to authenticated;
grant execute on function public.salvar_escala_turno(bigint, smallint, boolean, smallint, smallint, smallint, smallint) to authenticated;
grant execute on function public.excluir_escala_funcionario(bigint) to authenticated;
grant execute on function public.salvar_escala_funcionamento(smallint, smallint, smallint, smallint, smallint) to authenticated;

-- Sem papel liberado: so admin entra. Quando a rotina estiver rodando redonda,
-- basta incluir 'gerente' por permissoes.html, sem migration nova.
insert into public.pagina_permissao (pagina, papeis)
values ('escalas.html', array[]::text[])
on conflict (pagina) do nothing;

commit;
