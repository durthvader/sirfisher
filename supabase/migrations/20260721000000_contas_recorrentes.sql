-- Controle mensal de contas recorrentes.
-- Separa o cadastro da obrigacao (nome, vencimento, categoria, atividade)
-- dos pagamentos por competencia. O historico legado entra por RPC admin e
-- nunca precisa ser versionado no repositorio.

begin;

create table public.conta_recorrente (
  id bigint generated always as identity primary key,
  nome text not null check (length(btrim(nome)) between 2 and 160),
  dia_vencimento smallint not null check (dia_vencimento between 1 and 31),
  categoria text not null check (categoria in (
    'pessoal', 'ocupacao', 'servicos', 'operacao', 'tributos', 'financeiro', 'outros'
  )),
  tipo text not null default 'despesa' check (tipo in ('despesa', 'rotina')),
  unidade text not null default 'PRAIA' check (length(btrim(unidade)) between 2 and 40),
  ativa boolean not null default true,
  incluir_totais boolean not null default true,
  origem_legado text unique,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table public.conta_recorrente_pagamento (
  id bigint generated always as identity primary key,
  conta_id bigint not null references public.conta_recorrente(id) on delete restrict,
  competencia date not null check (competencia = date_trunc('month', competencia)::date),
  situacao text not null check (situacao in ('pago', 'sem_movimento')),
  valor numeric(14,2) check (valor is null or valor >= 0),
  conta_bancaria text,
  data_pagamento date,
  observacao text,
  origem text not null default 'manual' check (origem in ('manual', 'legado')),
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (conta_id, competencia),
  check (
    origem = 'legado'
    or situacao = 'sem_movimento'
    or (valor > 0 and nullif(btrim(conta_bancaria), '') is not null and data_pagamento is not null)
  ),
  check (
    situacao <> 'sem_movimento'
    or (valor is null and conta_bancaria is null and data_pagamento is null)
  )
);

create index conta_recorrente_ordem_idx
  on public.conta_recorrente (ativa desc, dia_vencimento, nome);
create index conta_recorrente_pagamento_competencia_idx
  on public.conta_recorrente_pagamento (competencia desc, conta_id);

comment on table public.conta_recorrente is
  'Cadastro das obrigacoes recorrentes e rotinas financeiras.';
comment on table public.conta_recorrente_pagamento is
  'Realizacao mensal por competencia de vencimento; a data de pagamento pode ser anterior ou posterior.';
comment on column public.conta_recorrente_pagamento.situacao is
  'pago registra desembolso; sem_movimento substitui marcadores simbolicos como R$ 0,01.';

alter table public.conta_recorrente enable row level security;
alter table public.conta_recorrente_pagamento enable row level security;
revoke all privileges on public.conta_recorrente from public, anon, authenticated;
revoke all privileges on public.conta_recorrente_pagamento from public, anon, authenticated;

create or replace function public.listar_contas_recorrentes(p_competencia date)
returns table (
  conta_id bigint,
  nome text,
  dia_vencimento smallint,
  categoria text,
  tipo text,
  unidade text,
  ativa boolean,
  incluir_totais boolean,
  pagamento_id bigint,
  situacao text,
  valor numeric,
  conta_bancaria text,
  data_pagamento date,
  observacao text,
  media_3 numeric,
  atualizado_por_nome text,
  atualizado_em timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_tem_papel(array['admin', 'socio']::text[]) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_competencia is null or p_competencia <> date_trunc('month', p_competencia)::date then
    raise exception using errcode = '22023', message = 'Competencia invalida.';
  end if;

  return query
  select
    c.id,
    c.nome,
    c.dia_vencimento,
    c.categoria,
    c.tipo,
    c.unidade,
    c.ativa,
    c.incluir_totais,
    p.id,
    p.situacao,
    p.valor,
    p.conta_bancaria,
    p.data_pagamento,
    p.observacao,
    m.media_3,
    coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name')::text,
    p.atualizado_em
  from public.conta_recorrente c
  left join public.conta_recorrente_pagamento p
    on p.conta_id = c.id and p.competencia = p_competencia
  left join auth.users u on u.id = p.atualizado_por
  left join lateral (
    select round(avg(x.valor), 2) as media_3
    from (
      select ph.valor
      from public.conta_recorrente_pagamento ph
      where ph.conta_id = c.id
        and ph.competencia < p_competencia
        and ph.situacao = 'pago'
        and ph.valor > 0
      order by ph.competencia desc
      limit 3
    ) x
  ) m on true
  order by c.dia_vencimento, c.nome;
end;
$function$;

create or replace view public.app_contas_recorrentes_pagamentos
with (security_barrier = true, security_invoker = false) as
select
  p.id,
  p.conta_id,
  c.nome,
  c.categoria,
  c.tipo,
  c.unidade,
  p.competencia,
  p.situacao,
  p.valor,
  p.conta_bancaria,
  p.data_pagamento,
  p.observacao,
  p.origem,
  coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name')::text as atualizado_por_nome,
  p.atualizado_em
from public.conta_recorrente_pagamento p
join public.conta_recorrente c on c.id = p.conta_id
left join auth.users u on u.id = p.atualizado_por
where public.usuario_tem_papel(array['admin', 'socio']::text[]);

create or replace view public.app_contas_recorrentes_totais
with (security_barrier = true, security_invoker = false) as
select
  p.competencia,
  sum(p.valor)::numeric(14,2) as total_pago,
  count(*)::integer as qtd_pagamentos
from public.conta_recorrente_pagamento p
join public.conta_recorrente c on c.id = p.conta_id
where p.situacao = 'pago'
  and c.tipo = 'despesa'
  and c.incluir_totais
  and public.usuario_tem_papel(array['admin', 'socio']::text[])
group by p.competencia;

create or replace function public.salvar_conta_recorrente(
  p_id bigint,
  p_nome text,
  p_dia_vencimento smallint,
  p_categoria text,
  p_tipo text default 'despesa',
  p_unidade text default 'PRAIA',
  p_ativa boolean default true,
  p_incluir_totais boolean default true
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id bigint;
begin
  if not public.usuario_tem_papel(array['admin', 'socio']::text[]) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_nome is null or length(btrim(p_nome)) < 2
     or p_dia_vencimento not between 1 and 31
     or p_categoria not in ('pessoal', 'ocupacao', 'servicos', 'operacao', 'tributos', 'financeiro', 'outros')
     or p_tipo not in ('despesa', 'rotina') then
    raise exception using errcode = '22023', message = 'Dados da conta invalidos.';
  end if;

  if p_id is null then
    insert into public.conta_recorrente (
      nome, dia_vencimento, categoria, tipo, unidade, ativa, incluir_totais, criado_por, atualizado_por
    ) values (
      btrim(p_nome), p_dia_vencimento, p_categoria, p_tipo,
      upper(coalesce(nullif(btrim(p_unidade), ''), 'PRAIA')),
      coalesce(p_ativa, true), coalesce(p_incluir_totais, true), auth.uid(), auth.uid()
    ) returning id into v_id;
  else
    update public.conta_recorrente
       set nome = btrim(p_nome),
           dia_vencimento = p_dia_vencimento,
           categoria = p_categoria,
           tipo = p_tipo,
           unidade = upper(coalesce(nullif(btrim(p_unidade), ''), 'PRAIA')),
           ativa = coalesce(p_ativa, true),
           incluir_totais = coalesce(p_incluir_totais, true),
           atualizado_por = auth.uid(),
           atualizado_em = now()
     where id = p_id
     returning id into v_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'Conta nao encontrada.';
    end if;
  end if;
  return v_id;
end;
$function$;

create or replace function public.salvar_pagamento_recorrente(
  p_conta_id bigint,
  p_competencia date,
  p_valor numeric,
  p_conta_bancaria text,
  p_data_pagamento date,
  p_sem_movimento boolean default false,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id bigint;
begin
  if not public.usuario_tem_papel(array['admin', 'socio']::text[]) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_competencia is null or p_competencia <> date_trunc('month', p_competencia)::date then
    raise exception using errcode = '22023', message = 'Competencia invalida.';
  end if;
  if not exists (select 1 from public.conta_recorrente c where c.id = p_conta_id) then
    raise exception using errcode = 'P0002', message = 'Conta nao encontrada.';
  end if;
  if not coalesce(p_sem_movimento, false) and (
    p_valor is null or p_valor <= 0
    or nullif(btrim(p_conta_bancaria), '') is null
    or p_data_pagamento is null
  ) then
    raise exception using errcode = '22023', message = 'Informe valor, conta bancaria e data de pagamento.';
  end if;

  insert into public.conta_recorrente_pagamento (
    conta_id, competencia, situacao, valor, conta_bancaria, data_pagamento,
    observacao, origem, criado_por, atualizado_por
  ) values (
    p_conta_id, p_competencia,
    case when coalesce(p_sem_movimento, false) then 'sem_movimento' else 'pago' end,
    case when coalesce(p_sem_movimento, false) then null else p_valor end,
    case when coalesce(p_sem_movimento, false) then null else btrim(p_conta_bancaria) end,
    case when coalesce(p_sem_movimento, false) then null else p_data_pagamento end,
    nullif(btrim(p_observacao), ''), 'manual', auth.uid(), auth.uid()
  )
  on conflict (conta_id, competencia) do update
    set situacao = excluded.situacao,
        valor = excluded.valor,
        conta_bancaria = excluded.conta_bancaria,
        data_pagamento = excluded.data_pagamento,
        observacao = excluded.observacao,
        origem = 'manual',
        atualizado_por = auth.uid(),
        atualizado_em = now()
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.excluir_pagamento_recorrente(
  p_conta_id bigint,
  p_competencia date
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_tem_papel(array['admin', 'socio']::text[]) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  delete from public.conta_recorrente_pagamento
   where conta_id = p_conta_id and competencia = p_competencia;
end;
$function$;

create or replace function public.importar_contas_recorrentes_legado(
  p_contas jsonb,
  p_pagamentos jsonb
)
returns table (contas_processadas integer, pagamentos_processados integer)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_item jsonb;
  v_conta_id bigint;
  v_chave text;
  v_categoria text;
  v_tipo text;
  v_sem_movimento boolean;
  v_valor numeric;
  v_competencia date;
  v_data_pagamento date;
  v_contas integer := 0;
  v_pagamentos integer := 0;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem importar o historico.';
  end if;
  if jsonb_typeof(p_contas) <> 'array' or jsonb_typeof(p_pagamentos) <> 'array'
     or jsonb_array_length(p_contas) > 250
     or jsonb_array_length(p_pagamentos) > 10000 then
    raise exception using errcode = '22023', message = 'Arquivo legado invalido ou acima do limite.';
  end if;

  for v_item in select value from jsonb_array_elements(p_contas)
  loop
    v_chave := nullif(btrim(v_item ->> 'chave'), '');
    v_categoria := coalesce(nullif(v_item ->> 'categoria', ''), 'outros');
    v_tipo := coalesce(nullif(v_item ->> 'tipo', ''), 'despesa');
    if v_chave is null
       or nullif(btrim(v_item ->> 'nome'), '') is null
       or (v_item ->> 'dia_vencimento')::integer not between 1 and 31
       or v_categoria not in ('pessoal', 'ocupacao', 'servicos', 'operacao', 'tributos', 'financeiro', 'outros')
       or v_tipo not in ('despesa', 'rotina') then
      raise exception using errcode = '22023', message = 'Cadastro legado invalido.';
    end if;

    insert into public.conta_recorrente (
      nome, dia_vencimento, categoria, tipo, unidade, ativa, incluir_totais, origem_legado,
      criado_por, atualizado_por
    ) values (
      btrim(v_item ->> 'nome'),
      (v_item ->> 'dia_vencimento')::smallint,
      v_categoria,
      v_tipo,
      upper(coalesce(nullif(btrim(v_item ->> 'unidade'), ''), 'PRAIA')),
      coalesce((v_item ->> 'ativa')::boolean, false),
      coalesce((v_item ->> 'incluir_totais')::boolean, true),
      v_chave,
      auth.uid(), auth.uid()
    )
    on conflict (origem_legado) do nothing;
    v_contas := v_contas + 1;
  end loop;

  for v_item in select value from jsonb_array_elements(p_pagamentos)
  loop
    v_chave := nullif(btrim(v_item ->> 'chave'), '');
    select c.id into v_conta_id
    from public.conta_recorrente c
    where c.origem_legado = v_chave;
    if not found then
      raise exception using errcode = '22023', message = 'Pagamento sem conta correspondente.';
    end if;

    v_competencia := (v_item ->> 'competencia')::date;
    if v_competencia <> date_trunc('month', v_competencia)::date then
      raise exception using errcode = '22023', message = 'Competencia legada invalida.';
    end if;
    v_sem_movimento := coalesce((v_item ->> 'sem_movimento')::boolean, false);
    v_valor := case when v_sem_movimento then null else nullif(v_item ->> 'valor', '')::numeric end;
    v_data_pagamento := nullif(v_item ->> 'data_pagamento', '')::date;

    insert into public.conta_recorrente_pagamento (
      conta_id, competencia, situacao, valor, conta_bancaria, data_pagamento,
      observacao, origem, criado_por, atualizado_por
    ) values (
      v_conta_id,
      v_competencia,
      case when v_sem_movimento then 'sem_movimento' else 'pago' end,
      v_valor,
      case when v_sem_movimento then null else nullif(btrim(v_item ->> 'conta_bancaria'), '') end,
      case when v_sem_movimento then null else v_data_pagamento end,
      nullif(btrim(v_item ->> 'observacao'), ''),
      'legado', auth.uid(), auth.uid()
    )
    on conflict (conta_id, competencia) do update
      set situacao = case
            when public.conta_recorrente_pagamento.origem = 'manual'
              then public.conta_recorrente_pagamento.situacao
            else excluded.situacao
          end,
          valor = case
            when public.conta_recorrente_pagamento.origem = 'manual'
              then public.conta_recorrente_pagamento.valor
            else excluded.valor
          end,
          conta_bancaria = case
            when public.conta_recorrente_pagamento.origem = 'manual'
              then public.conta_recorrente_pagamento.conta_bancaria
            else excluded.conta_bancaria
          end,
          data_pagamento = case
            when public.conta_recorrente_pagamento.origem = 'manual'
              then public.conta_recorrente_pagamento.data_pagamento
            else excluded.data_pagamento
          end,
          observacao = case
            when public.conta_recorrente_pagamento.origem = 'manual'
              then public.conta_recorrente_pagamento.observacao
            else excluded.observacao
          end,
          origem = case
            when public.conta_recorrente_pagamento.origem = 'manual' then 'manual'
            else 'legado'
          end,
          atualizado_por = case
            when public.conta_recorrente_pagamento.origem = 'manual'
              then public.conta_recorrente_pagamento.atualizado_por
            else auth.uid()
          end,
          atualizado_em = case
            when public.conta_recorrente_pagamento.origem = 'manual'
              then public.conta_recorrente_pagamento.atualizado_em
            else now()
          end;
    v_pagamentos := v_pagamentos + 1;
  end loop;

  return query select v_contas, v_pagamentos;
end;
$function$;

revoke all privileges on function public.listar_contas_recorrentes(date) from public, anon, authenticated;
revoke all privileges on function public.salvar_conta_recorrente(bigint, text, smallint, text, text, text, boolean, boolean) from public, anon, authenticated;
revoke all privileges on function public.salvar_pagamento_recorrente(bigint, date, numeric, text, date, boolean, text) from public, anon, authenticated;
revoke all privileges on function public.excluir_pagamento_recorrente(bigint, date) from public, anon, authenticated;
revoke all privileges on function public.importar_contas_recorrentes_legado(jsonb, jsonb) from public, anon, authenticated;

grant execute on function public.listar_contas_recorrentes(date) to authenticated;
grant execute on function public.salvar_conta_recorrente(bigint, text, smallint, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.salvar_pagamento_recorrente(bigint, date, numeric, text, date, boolean, text) to authenticated;
grant execute on function public.excluir_pagamento_recorrente(bigint, date) to authenticated;
grant execute on function public.importar_contas_recorrentes_legado(jsonb, jsonb) to authenticated;

revoke all privileges on public.app_contas_recorrentes_pagamentos from public, anon, authenticated;
revoke all privileges on public.app_contas_recorrentes_totais from public, anon, authenticated;
grant select on public.app_contas_recorrentes_pagamentos to authenticated;
grant select on public.app_contas_recorrentes_totais to authenticated;

insert into public.pagina_permissao (pagina, papeis)
values ('contas_recorrentes.html', array['socio'])
on conflict (pagina) do nothing;

commit;
