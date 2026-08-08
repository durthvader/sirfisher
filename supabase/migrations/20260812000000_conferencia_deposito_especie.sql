-- Conferencia entre as sangrias marcadas como depositadas em venda_especie.html
-- e os depositos em dinheiro que realmente entraram no Banco do Brasil.
--
-- Regra de negocio confirmada com o usuario: 100% do dinheiro em especie
-- recolhido no quiosque e depositado no BB, entao todo lancamento
-- "Dep dinheiro%" de raw_bb corresponde a sangria. Isso torna o saldo
-- acumulado (marcado - extrato - justificativas) o controle mais forte, porque
-- ele independe de acertar de qual dia veio cada nota.
--
-- Por que o casamento e por lote, e nao 1:1 por sangria:
--   - varias sangrias sao marcadas como depositadas na mesma sessao, ou seja,
--     uma unica ida ao caixa eletronico;
--   - o mesmo dinheiro entra no extrato fatiado em varios envelopes, por causa
--     do limite do ATM.
-- A unidade de conferencia e a ida ao banco: N sangrias contra M lancamentos.
--
-- Por que existe data de corte:
--   Antes de 2026-07-21 o campo depositada_em e carimbo das migrations de
--   backfill (20260718000000 preencheu depositada_em com a propria data da
--   sangria para fechar o ciclo dos registros antigos), nao deposito real. Sem
--   o corte a tela mostraria centenas de divergencias falsas e o painel perderia
--   a serventia de alarme.
--
-- Objetos criados (nenhum objeto existente e alterado ou removido):
--   + public.conferencia_deposito_ajuste                  tabela + RLS sem policy
--   + public.registrar_ajuste_conferencia_deposito(...)   RPC
--   + public.desfazer_ajuste_conferencia_deposito(bigint) RPC
--   + public.app_conferencia_deposito_especie             lotes (localizador)
--   + public.app_conferencia_deposito_especie_resumo      acumulado (alarme)
--   + public.app_conferencia_deposito_ajustes             historico auditado
--
-- As views seguem o padrao app_* do projeto: security_barrier = true,
-- security_invoker = false, checagem de permissao no WHERE e grant apenas para
-- authenticated. O aviso security_definer_view do Security Advisor sobre elas e
-- aceito, conforme decisao registrada no AGENTS.md.

begin;

-- ---------------------------------------------------------------------------
-- Justificativas de divergencia
-- ---------------------------------------------------------------------------
-- Sem esta valvula, uma diferenca explicada (por exemplo, dinheiro que saiu de
-- outra conta e foi marcado como deposito em especie) ficaria na diferenca
-- acumulada para sempre. O painel viveria vermelho, todo mundo se acostumaria
-- com o numero errado e o alarme deixaria de alarmar.
--
-- Convencao de sinal: valor positivo explica dinheiro marcado como depositado
-- que nao entrou no BB; valor negativo explica dinheiro que entrou no BB sem
-- sangria marcada correspondente.

create table if not exists public.conferencia_deposito_ajuste (
  id bigint generated always as identity primary key,
  data date not null,
  valor numeric(14, 2) not null,
  motivo text not null,
  criado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  desfeito_por uuid references auth.users(id) on delete set null,
  desfeito_em timestamptz,
  constraint conferencia_deposito_ajuste_valor_nao_zero
    check (valor <> 0),
  constraint conferencia_deposito_ajuste_motivo_preenchido
    check (btrim(motivo) <> '')
);

comment on table public.conferencia_deposito_ajuste is
  'Justificativas auditadas de divergencia entre sangria marcada como depositada e deposito em dinheiro no BB.';
comment on column public.conferencia_deposito_ajuste.data is
  'Data do lote de deposito a que a justificativa se refere.';
comment on column public.conferencia_deposito_ajuste.valor is
  'Positivo explica marcado que nao entrou no BB; negativo explica entrada no BB sem sangria marcada.';
comment on column public.conferencia_deposito_ajuste.motivo is
  'Texto obrigatorio: se as excecoes virarem rotina, o historico denuncia.';

create index if not exists ix_conferencia_deposito_ajuste_data
  on public.conferencia_deposito_ajuste (data)
  where desfeito_em is null;

-- RLS ligado sem policy nega tudo por padrao. O acesso e exclusivamente pelas
-- views app_* e pelas RPCs, no mesmo padrao de ajuste_manual e de_para.
alter table public.conferencia_deposito_ajuste enable row level security;
revoke all privileges on table public.conferencia_deposito_ajuste
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Lotes de deposito (localizador da divergencia)
-- ---------------------------------------------------------------------------

create or replace view public.app_conferencia_deposito_especie
with (security_barrier = true, security_invoker = false) as
with corte as (
  select date '2026-07-21' as inicio
),
marcadas as (
  select
    v.valor,
    v.depositada_em,
    v.depositada_por,
    -- Abre um lote novo quando ha mais de 10 minutos de intervalo entre duas
    -- marcacoes. Uma ida ao banco produz marcacoes a segundos de distancia.
    case
      when lag(v.depositada_em) over (order by v.depositada_em) is null then 1
      when v.depositada_em - lag(v.depositada_em) over (order by v.depositada_em)
           > interval '10 minutes' then 1
      else 0
    end as abre_lote
  from public.venda_especie v
  cross join corte c
  where v.unidade = 'PRAIA'
    and v.depositada_em is not null
    and v.valor > 0
    and (v.depositada_em at time zone 'America/Sao_Paulo')::date >= c.inicio
),
numeradas as (
  select
    m.*,
    sum(m.abre_lote) over (
      order by m.depositada_em
      rows between unbounded preceding and current row
    ) as lote
  from marcadas m
),
lotes as (
  select
    n.lote,
    (min(n.depositada_em) at time zone 'America/Sao_Paulo')::date as data_lote,
    min(n.depositada_em) as marcado_em,
    count(*)::int as qtd_sangrias,
    sum(n.valor)::numeric(14, 2) as marcado,
    -- Postgres 17 nao tem min(uuid); pega o responsavel da primeira marcacao
    -- do lote, que e quem foi ao banco.
    private.nome_exibicao_usuario(
      (array_agg(n.depositada_por order by n.depositada_em))[1]
    ) as marcado_por_nome
  from numeradas n
  group by n.lote
),
depositos as (
  select b.id, b.data, b.valor
  from public.raw_bb b
  cross join corte c
  where b.lancamento ilike 'Dep dinheiro%'
    and b.data >= c.inicio - 1
),
-- Cada lancamento do extrato entra em um unico lote: o mais proximo dentro da
-- janela D-1 a D+2. A janela cobre deposito noturno creditado no dia seguinte e
-- marcacao feita alguns dias depois da ida ao banco. O distinct on impede que o
-- mesmo lancamento seja contado em dois lotes.
deposito_do_lote as (
  select distinct on (d.id)
    d.id,
    d.data,
    d.valor,
    l.lote
  from depositos d
  left join lotes l
    on d.data between l.data_lote - 1 and l.data_lote + 2
  order by d.id, abs(d.data - l.data_lote) nulls last, l.data_lote
),
extrato as (
  select
    lote,
    count(*)::int as qtd_lancamentos,
    sum(valor)::numeric(14, 2) as extrato
  from deposito_do_lote
  where lote is not null
  group by lote
),
orfaos as (
  select
    d.data,
    count(*)::int as qtd_lancamentos,
    sum(d.valor)::numeric(14, 2) as extrato
  from deposito_do_lote d
  where d.lote is null
  group by d.data
),
ajustes as (
  select a.data, sum(a.valor)::numeric(14, 2) as ajuste
  from public.conferencia_deposito_ajuste a
  where a.desfeito_em is null
  group by a.data
)
select
  l.data_lote as data,
  l.marcado_em,
  l.marcado_por_nome,
  l.qtd_sangrias,
  l.marcado,
  coalesce(e.extrato, 0)::numeric(14, 2) as extrato,
  coalesce(e.qtd_lancamentos, 0) as qtd_lancamentos,
  coalesce(aj.ajuste, 0)::numeric(14, 2) as ajuste,
  (l.marcado - coalesce(e.extrato, 0) - coalesce(aj.ajuste, 0))::numeric(14, 2) as diferenca,
  case
    when l.marcado - coalesce(e.extrato, 0) - coalesce(aj.ajuste, 0) = 0 then 'conferido'
    when coalesce(e.extrato, 0) = 0 then 'sem_extrato'
    when l.marcado - coalesce(e.extrato, 0) - coalesce(aj.ajuste, 0) > 0 then 'falta_no_banco'
    else 'sobra_no_banco'
  end as status
from lotes l
left join extrato e on e.lote = l.lote
left join ajustes aj on aj.data = l.data_lote
where public.usuario_pode_acessar_alguma_pagina(array['venda_especie.html'])
union all
-- Dinheiro que entrou no BB sem nenhum lote por perto. Como 100% do deposito em
-- especie vem de sangria, isso e sangria que ninguem marcou.
select
  o.data,
  null::timestamptz,
  null::text,
  0,
  0::numeric(14, 2),
  o.extrato,
  o.qtd_lancamentos,
  0::numeric(14, 2),
  (0 - o.extrato)::numeric(14, 2),
  'sem_lote'
from orfaos o
where public.usuario_pode_acessar_alguma_pagina(array['venda_especie.html']);

comment on view public.app_conferencia_deposito_especie is
  'Lotes de deposito de sangria confrontados com os lancamentos Dep dinheiro do extrato do BB.';

-- ---------------------------------------------------------------------------
-- Acumulado (alarme)
-- ---------------------------------------------------------------------------
-- Soma os dois lados inteiros no periodo confiavel. Imune a erro de data: se
-- uma nota mudou de viagem, o lote acusa mas o acumulado continua zerado.

create or replace view public.app_conferencia_deposito_especie_resumo
with (security_barrier = true, security_invoker = false) as
with corte as (
  select date '2026-07-21' as inicio
),
marcado as (
  select coalesce(sum(v.valor), 0)::numeric(14, 2) as total
  from public.venda_especie v
  cross join corte c
  where v.unidade = 'PRAIA'
    and v.depositada_em is not null
    and (v.depositada_em at time zone 'America/Sao_Paulo')::date >= c.inicio
),
banco as (
  select
    coalesce(sum(b.valor), 0)::numeric(14, 2) as total,
    max(b.data) as ultimo_deposito
  from public.raw_bb b
  cross join corte c
  where b.lancamento ilike 'Dep dinheiro%'
    and b.data >= c.inicio - 1
),
extrato_ate as (
  select max(b.data) as ate from public.raw_bb b
),
ajuste as (
  select coalesce(sum(a.valor), 0)::numeric(14, 2) as total
  from public.conferencia_deposito_ajuste a
  cross join corte c
  where a.desfeito_em is null
    and a.data >= c.inicio
),
pendente as (
  select coalesce(sum(v.valor), 0)::numeric(14, 2) as total
  from public.venda_especie v
  where v.unidade = 'PRAIA'
    and v.depositada_em is null
)
select
  c.inicio as desde,
  m.total as marcado_depositado,
  b.total as recebido_banco,
  aj.total as ajustes_justificados,
  (m.total - b.total - aj.total)::numeric(14, 2) as diferenca,
  b.ultimo_deposito,
  -- Sem isso, deposito recente aparece como "nao chegou no banco" quando o
  -- atrasado e o extrato. A tela precisa mostrar ate quando ela enxerga.
  ea.ate as extrato_ate,
  p.total as pendente_deposito
from corte c
cross join marcado m
cross join banco b
cross join extrato_ate ea
cross join ajuste aj
cross join pendente p
where public.usuario_pode_acessar_alguma_pagina(array['venda_especie.html']);

comment on view public.app_conferencia_deposito_especie_resumo is
  'Saldo acumulado da conferencia de deposito em especie: marcado - extrato - justificativas.';

-- ---------------------------------------------------------------------------
-- Historico das justificativas
-- ---------------------------------------------------------------------------

create or replace view public.app_conferencia_deposito_ajustes
with (security_barrier = true, security_invoker = false) as
select
  a.id,
  a.data,
  a.valor,
  a.motivo,
  a.criado_em,
  private.nome_exibicao_usuario(a.criado_por) as criado_por_nome,
  a.desfeito_em,
  private.nome_exibicao_usuario(a.desfeito_por) as desfeito_por_nome
from public.conferencia_deposito_ajuste a
where public.usuario_pode_acessar_alguma_pagina(array['venda_especie.html']);

comment on view public.app_conferencia_deposito_ajustes is
  'Historico auditado das justificativas de divergencia, com autor e momento.';

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

create or replace function public.registrar_ajuste_conferencia_deposito(
  p_data date,
  p_valor numeric,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id bigint;
  v_usuario uuid := auth.uid();
begin
  if not public.usuario_pode_acessar_pagina('venda_especie.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_data is null then
    raise exception using errcode = '22023', message = 'Informe a data do lote.';
  end if;
  if p_valor is null or round(p_valor, 2) = 0 then
    raise exception using errcode = '22023', message = 'Informe um valor diferente de zero.';
  end if;
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception using errcode = '22023', message = 'Descreva o motivo da justificativa.';
  end if;

  insert into public.conferencia_deposito_ajuste (data, valor, motivo, criado_por)
  values (p_data, round(p_valor, 2), btrim(p_motivo), v_usuario)
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.desfazer_ajuste_conferencia_deposito(
  p_id bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_usuario uuid := auth.uid();
begin
  if not public.usuario_pode_acessar_pagina('venda_especie.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  -- Desfazer preserva a linha: quem justificou, quem desfez e quando ficam no
  -- historico. Nada de exclusao fisica em trilha de auditoria.
  update public.conferencia_deposito_ajuste
     set desfeito_em = now(),
         desfeito_por = v_usuario
   where id = p_id
     and desfeito_em is null;

  if not found then
    raise exception using errcode = 'P0002',
      message = 'Justificativa nao encontrada ou ja desfeita.';
  end if;
end;
$function$;

-- ---------------------------------------------------------------------------
-- Permissoes
-- ---------------------------------------------------------------------------

revoke all privileges on function
  public.registrar_ajuste_conferencia_deposito(date, numeric, text)
  from public, anon;
revoke all privileges on function
  public.desfazer_ajuste_conferencia_deposito(bigint)
  from public, anon;
grant execute on function
  public.registrar_ajuste_conferencia_deposito(date, numeric, text)
  to authenticated;
grant execute on function
  public.desfazer_ajuste_conferencia_deposito(bigint)
  to authenticated;

revoke all privileges on public.app_conferencia_deposito_especie from public, anon;
revoke all privileges on public.app_conferencia_deposito_especie_resumo from public, anon;
revoke all privileges on public.app_conferencia_deposito_ajustes from public, anon;
grant select on public.app_conferencia_deposito_especie to authenticated;
grant select on public.app_conferencia_deposito_especie_resumo to authenticated;
grant select on public.app_conferencia_deposito_ajustes to authenticated;

commit;
