-- Consolida a operacao em uma unica unidade e separa unidade de conta/origem.
-- Os valores atuais viram defaults editaveis e as participacoes vigentes de
-- cada origem sao preservadas para que a migracao nao altere os indicadores.

begin;

-- Snapshot privado e idempotente dos campos que serao consolidados. Ele nao
-- copia valores financeiros nem fica acessivel pela Data API; serve para uma
-- reversao auditavel dos vinculos de unidade/conta, se necessaria.
create table if not exists private.migracao_unidade_unica_backup_20260818 (
  objeto text not null,
  chave text not null,
  dados jsonb not null,
  registrado_em timestamptz not null default now(),
  primary key (objeto, chave)
);

alter table private.migracao_unidade_unica_backup_20260818 enable row level security;
revoke all privileges on table private.migracao_unidade_unica_backup_20260818
  from public, anon, authenticated;

insert into private.migracao_unidade_unica_backup_20260818 (objeto, chave, dados)
select 'unidade', u.id::text,
       jsonb_build_object('id', u.id, 'nome', u.nome, 'ativa', u.ativa)
from public.unidade u
on conflict (objeto, chave) do nothing;

insert into private.migracao_unidade_unica_backup_20260818 (objeto, chave, dados)
select 'conta', c.id::text,
       jsonb_build_object('id', c.id, 'nome', c.nome, 'banco', c.banco,
                          'unidade_id', c.unidade_id, 'ativa', c.ativa)
from public.conta c
on conflict (objeto, chave) do nothing;

insert into private.migracao_unidade_unica_backup_20260818 (objeto, chave, dados)
select 'venda_especie', v.id::text,
       jsonb_build_object('id', v.id, 'unidade', v.unidade)
from public.venda_especie v
on conflict (objeto, chave) do nothing;

insert into private.migracao_unidade_unica_backup_20260818 (objeto, chave, dados)
select 'conta_recorrente', c.id::text,
       jsonb_build_object('id', c.id, 'unidade', c.unidade)
from public.conta_recorrente c
on conflict (objeto, chave) do nothing;

insert into private.migracao_unidade_unica_backup_20260818 (objeto, chave, dados)
select 'stone_estabelecimento', e.stonecode,
       jsonb_build_object('stonecode', e.stonecode, 'unidade', e.unidade,
                          'descricao', e.descricao)
from public.stone_estabelecimento e
on conflict (objeto, chave) do nothing;

insert into private.migracao_unidade_unica_backup_20260818 (objeto, chave, dados)
select 'raw_stone_vendas', v.id::text,
       jsonb_build_object('id', v.id, 'conta_id', v.conta_id)
from public.raw_stone_vendas v
on conflict (objeto, chave) do nothing;

insert into private.migracao_unidade_unica_backup_20260818 (objeto, chave, dados)
select 'raw_stone_recebiveis', r.id::text,
       jsonb_build_object('id', r.id, 'conta_id', r.conta_id)
from public.raw_stone_recebiveis r
on conflict (objeto, chave) do nothing;

-- ---------------------------------------------------------------------------
-- Catalogo tipado de parametros
-- ---------------------------------------------------------------------------

alter table public.parametros
  add column if not exists grupo text not null default 'Geral',
  add column if not exists unidade_medida text not null default 'numero',
  add column if not exists valor_min numeric,
  add column if not exists valor_max numeric,
  add column if not exists ordem integer not null default 100;

insert into public.parametros (chave, valor, descricao) values
  ('alerta_cmv_vermelho', 38, 'CMV que aciona alerta vermelho'),
  ('alerta_pessoal_vermelho', 30, 'Custo de pessoal que aciona alerta vermelho'),
  ('meta_proxima_perc', 90, 'Percentual a partir do qual a meta esta proxima'),
  ('meta_atingida_perc', 100, 'Percentual a partir do qual a meta esta atingida'),
  ('concentracao_fornecedor_ambar', 60, 'Concentracao nos maiores fornecedores que aciona alerta amarelo'),
  ('concentracao_fornecedor_vermelho', 66, 'Concentracao nos maiores fornecedores que aciona alerta vermelho'),
  ('vazamento_novo_valor', 3000, 'Valor minimo para alertar fornecedor novo'),
  ('vazamento_aumento_perc', 35, 'Aumento percentual minimo para alertar gasto fora do padrao'),
  ('vazamento_excesso_valor', 1500, 'Excesso minimo em reais para alertar gasto fora do padrao'),
  ('vazamento_meses_base', 2, 'Quantidade minima de meses para comparar gasto recorrente'),
  ('caixa_saldo_minimo', 100000, 'Saldo minimo de seguranca do caixa'),
  ('caixa_dias_critico', 30, 'Dias ate o saldo minimo que indicam situacao critica'),
  ('caixa_dias_atencao', 60, 'Dias ate o saldo minimo que indicam atencao'),
  ('caixa_horizonte_dias', 90, 'Dias futuros exibidos na curva de caixa'),
  ('bonus_gerente_percentual', 2, 'Percentual da variacao positiva usado na bonificacao'),
  ('bonus_gerente_teto', 600, 'Teto da previsao de bonificacao do gerente'),
  ('conciliacao_tolerancia_valor', 0.01, 'Tolerancia monetaria para conciliacao'),
  ('conciliacao_janela_dias', 5, 'Janela em dias para procurar contrapartida'),
  ('estorno_janela_dias', 1, 'Janela em dias para procurar reversao na mesma conta'),
  ('estorno_forte_minutos', 60, 'Intervalo maximo em minutos para indicio forte de estorno'),
  ('deposito_lote_intervalo_minutos', 10, 'Intervalo que separa lotes de marcacao de deposito'),
  ('deposito_janela_anterior_dias', 1, 'Dias anteriores considerados no casamento de deposito'),
  ('deposito_janela_posterior_dias', 2, 'Dias posteriores considerados no casamento de deposito'),
  ('deposito_tolerancia_valor', 0.01, 'Tolerancia monetaria na conferencia de deposito'),
  ('dre_cmv_referencia_min', 28, 'Limite inferior de referencia para CMV'),
  ('dre_cmv_referencia_max', 35, 'Limite superior de referencia para CMV'),
  ('dre_pessoal_referencia_min', 25, 'Limite inferior de referencia para pessoal'),
  ('dre_pessoal_referencia_max', 35, 'Limite superior de referencia para pessoal'),
  ('dre_prime_cost_referencia_min', 55, 'Limite inferior de referencia para prime cost'),
  ('dre_prime_cost_referencia_max', 65, 'Limite superior de referencia para prime cost')
on conflict (chave) do nothing;

update public.parametros
set grupo = case
      when chave in ('alerta_cmv_vermelho', 'alerta_pessoal_vermelho',
                     'meta_proxima_perc', 'meta_atingida_perc',
                     'dre_cmv_referencia_min', 'dre_cmv_referencia_max',
                     'dre_pessoal_referencia_min', 'dre_pessoal_referencia_max',
                     'dre_prime_cost_referencia_min', 'dre_prime_cost_referencia_max')
        then 'Indicadores e metas'
      when chave like 'concentracao_%' or chave like 'vazamento_%'
        then 'Alertas de despesas'
      when chave like 'caixa_%' then 'Caixa'
      when chave like 'bonus_%' then 'Bonificacao'
      when chave like 'conciliacao_%' or chave like 'estorno_%' or chave like 'deposito_%'
        then 'Conciliacao'
      else coalesce(nullif(grupo, 'Geral'), 'Projecoes')
    end,
    unidade_medida = case
      when chave in (
        'dias_provisao_estoque', 'caixa_dias_critico', 'caixa_dias_atencao',
        'caixa_horizonte_dias', 'conciliacao_janela_dias',
        'estorno_janela_dias', 'deposito_janela_anterior_dias',
        'deposito_janela_posterior_dias'
      ) then 'dias'
      when chave in (
        'horizonte_meses', 'meses_media_fixa', 'vazamento_meses_base'
      ) then 'meses'
      when chave = 'perc_despesa_direta' then 'proporcao'
      when chave like '%_perc' or chave like '%_percentual'
        or chave like '%_vermelho' or chave like '%_ambar'
        or chave like '%_referencia_min' or chave like '%_referencia_max'
        then 'percentual'
      when chave like '%_dias' or chave = 'caixa_horizonte_dias' then 'dias'
      when chave like '%_minutos' then 'minutos'
      when chave like '%_valor' or chave in ('caixa_saldo_minimo', 'bonus_gerente_teto') then 'reais'
      when chave like '%_meses%' then 'meses'
      else unidade_medida
    end,
    valor_min = case
      when chave in ('horizonte_meses', 'meses_media_fixa',
                     'vazamento_meses_base', 'caixa_horizonte_dias',
                     'deposito_lote_intervalo_minutos') then 1
      when chave in ('meta_atingida_perc', 'meta_proxima_perc') then 0
      when chave like '%_perc' or chave like '%_percentual'
        or chave like '%_vermelho' or chave like '%_ambar'
        or chave like '%_referencia_min' or chave like '%_referencia_max' then 0
      else 0
    end,
    valor_max = case
      when chave = 'perc_despesa_direta' then 1
      when chave in ('alerta_cmv_vermelho', 'alerta_pessoal_vermelho',
                     'concentracao_fornecedor_ambar', 'concentracao_fornecedor_vermelho',
                     'bonus_gerente_percentual',
                     'dre_cmv_referencia_min', 'dre_cmv_referencia_max',
                     'dre_pessoal_referencia_min', 'dre_pessoal_referencia_max',
                     'dre_prime_cost_referencia_min', 'dre_prime_cost_referencia_max') then 100
      else null
    end,
    ordem = case chave
      when 'horizonte_meses' then 10
      when 'meses_media_fixa' then 20
      when 'dias_provisao_estoque' then 30
      when 'perc_despesa_direta' then 40
      when 'peso_feriado' then 50
      when 'alerta_cmv_vermelho' then 100
      when 'alerta_pessoal_vermelho' then 110
      when 'meta_proxima_perc' then 120
      when 'meta_atingida_perc' then 130
      when 'concentracao_fornecedor_ambar' then 200
      when 'concentracao_fornecedor_vermelho' then 210
      when 'vazamento_novo_valor' then 220
      when 'vazamento_aumento_perc' then 230
      when 'vazamento_excesso_valor' then 240
      when 'vazamento_meses_base' then 250
      when 'caixa_saldo_minimo' then 300
      when 'caixa_dias_critico' then 310
      when 'caixa_dias_atencao' then 320
      when 'caixa_horizonte_dias' then 330
      when 'bonus_gerente_percentual' then 400
      when 'bonus_gerente_teto' then 410
      when 'conciliacao_tolerancia_valor' then 500
      when 'conciliacao_janela_dias' then 510
      when 'estorno_janela_dias' then 520
      when 'estorno_forte_minutos' then 530
      when 'deposito_lote_intervalo_minutos' then 540
      when 'deposito_janela_anterior_dias' then 550
      when 'deposito_janela_posterior_dias' then 560
      when 'deposito_tolerancia_valor' then 570
      else ordem
    end;

create or replace function public.parametro_valor(p_chave text, p_padrao numeric)
returns numeric
language sql
stable
security invoker
set search_path = pg_catalog, pg_temp
as $$
  select coalesce((select p.valor from public.parametros p where p.chave = p_chave), p_padrao);
$$;

create or replace function public.admin_listar_parametros()
returns setof public.parametros
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem ver os parametros.';
  end if;
  return query
  select p.* from public.parametros p order by p.grupo, p.ordem, p.chave;
end;
$$;

create or replace function public.admin_salvar_parametro(p_chave text, p_valor numeric)
returns public.parametros
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_anterior public.parametros;
  v_row public.parametros;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem alterar parametros.';
  end if;
  if p_valor is null then
    raise exception using errcode = '22023', message = 'Valor obrigatorio.';
  end if;

  select * into v_anterior from public.parametros where chave = p_chave for update;
  if not found then
    raise exception using errcode = '22023', message = 'Parametro desconhecido: ' || coalesce(p_chave, '(nulo)');
  end if;
  if v_anterior.valor_min is not null and p_valor < v_anterior.valor_min then
    raise exception using errcode = '22023', message = 'Valor abaixo do minimo permitido.';
  end if;
  if v_anterior.valor_max is not null and p_valor > v_anterior.valor_max then
    raise exception using errcode = '22023', message = 'Valor acima do maximo permitido.';
  end if;
  if v_anterior.unidade_medida in ('dias', 'meses', 'minutos')
     and p_valor <> trunc(p_valor) then
    raise exception using errcode = '22023', message = 'Este parametro exige um numero inteiro.';
  end if;

  if p_chave = 'meta_proxima_perc'
     and p_valor > public.parametro_valor('meta_atingida_perc', 100) then
    raise exception using errcode = '22023', message = 'Meta proxima nao pode superar a meta atingida.';
  elsif p_chave = 'meta_atingida_perc'
     and p_valor < public.parametro_valor('meta_proxima_perc', 90) then
    raise exception using errcode = '22023', message = 'Meta atingida nao pode ficar abaixo da meta proxima.';
  elsif p_chave = 'concentracao_fornecedor_ambar'
     and p_valor > public.parametro_valor('concentracao_fornecedor_vermelho', 66) then
    raise exception using errcode = '22023', message = 'Limite amarelo nao pode superar o vermelho.';
  elsif p_chave = 'concentracao_fornecedor_vermelho'
     and p_valor < public.parametro_valor('concentracao_fornecedor_ambar', 60) then
    raise exception using errcode = '22023', message = 'Limite vermelho nao pode ficar abaixo do amarelo.';
  elsif p_chave = 'caixa_dias_critico'
     and p_valor > public.parametro_valor('caixa_dias_atencao', 60) then
    raise exception using errcode = '22023', message = 'Prazo critico nao pode superar o prazo de atencao.';
  elsif p_chave = 'caixa_dias_atencao'
     and (p_valor < public.parametro_valor('caixa_dias_critico', 30)
          or p_valor > public.parametro_valor('caixa_horizonte_dias', 90)) then
    raise exception using errcode = '22023', message = 'Prazo de atencao deve ficar entre o critico e o horizonte.';
  elsif p_chave = 'caixa_horizonte_dias'
     and p_valor < public.parametro_valor('caixa_dias_atencao', 60) then
    raise exception using errcode = '22023', message = 'Horizonte deve ser igual ou maior que o prazo de atencao.';
  elsif p_chave in ('dre_cmv_referencia_min', 'dre_pessoal_referencia_min',
                    'dre_prime_cost_referencia_min')
     and p_valor > public.parametro_valor(replace(p_chave, '_min', '_max'), 100) then
    raise exception using errcode = '22023', message = 'Limite minimo nao pode superar o maximo.';
  elsif p_chave in ('dre_cmv_referencia_max', 'dre_pessoal_referencia_max',
                    'dre_prime_cost_referencia_max')
     and p_valor < public.parametro_valor(replace(p_chave, '_max', '_min'), 0) then
    raise exception using errcode = '22023', message = 'Limite maximo nao pode ficar abaixo do minimo.';
  end if;

  update public.parametros set valor = p_valor
  where chave = p_chave
  returning * into v_row;

  if v_anterior.valor is distinct from v_row.valor then
    insert into private.parametro_historico(chave, valor_anterior, valor_novo, alterado_por)
    values (v_row.chave, v_anterior.valor, v_row.valor, auth.uid());
  end if;
  return v_row;
end;
$$;

revoke all privileges on function public.parametro_valor(text, numeric) from public, anon, authenticated;
grant execute on function public.parametro_valor(text, numeric) to anon, authenticated;
revoke all privileges on function public.admin_listar_parametros() from public, anon, authenticated;
grant execute on function public.admin_listar_parametros() to authenticated;
revoke all privileges on function public.admin_salvar_parametro(text, numeric) from public, anon, authenticated;
grant execute on function public.admin_salvar_parametro(text, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- Configuracao operacional de uma unica unidade
-- ---------------------------------------------------------------------------

create table if not exists public.configuracao_operacional (
  singleton boolean primary key default true check (singleton),
  unidade_principal_id smallint not null references public.unidade(id),
  unidade_exibicao text not null check (char_length(btrim(unidade_exibicao)) between 1 and 80),
  conta_deposito_id smallint references public.conta(id),
  conferencia_deposito_desde date not null default date '2026-07-21',
  deposito_descricao_padrao text not null default 'Dep dinheiro%',
  fuso_horario text not null default 'America/Sao_Paulo',
  atualizado_por uuid,
  atualizado_em timestamptz not null default now()
);

insert into public.configuracao_operacional (
  singleton, unidade_principal_id, unidade_exibicao, conta_deposito_id
)
select
  true,
  u.id,
  u.nome,
  (select c.id from public.conta c where c.nome = 'Banco do Brasil' order by c.id limit 1)
from public.unidade u
order by case when u.id = (
  select c.unidade_id from public.conta c where c.nome = 'Stone' order by c.id limit 1
) then 0 else 1 end, u.ativa desc, u.id
limit 1
on conflict (singleton) do nothing;

do $validacao_config$
begin
  if not exists (
    select 1 from public.configuracao_operacional where singleton
  ) then
    raise exception 'Nenhuma unidade valida foi encontrada para inicializar a configuracao operacional.';
  end if;
end;
$validacao_config$;

create table if not exists private.configuracao_operacional_historico (
  id bigint generated always as identity primary key,
  configuracao_anterior jsonb not null,
  configuracao_nova jsonb not null,
  alterado_por uuid,
  alterado_em timestamptz not null default now()
);

alter table public.configuracao_operacional enable row level security;
alter table private.configuracao_operacional_historico enable row level security;
revoke all privileges on table public.configuracao_operacional from public, anon, authenticated;
revoke all privileges on table private.configuracao_operacional_historico from public, anon, authenticated;

create or replace function public.unidade_principal_nome()
returns text
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select u.nome
  from public.configuracao_operacional c
  join public.unidade u on u.id = c.unidade_principal_id
  where c.singleton = true;
$$;

create or replace function public.app_configuracao_operacional()
returns table (unidade_codigo text, unidade_nome text, parametros jsonb)
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select
    public.unidade_principal_nome(),
    (select c.unidade_exibicao from public.configuracao_operacional c where c.singleton),
    coalesce((select jsonb_object_agg(p.chave, p.valor) from public.parametros p), '{}'::jsonb);
$$;

create or replace function public.admin_obter_configuracao_operacional()
returns table (
  unidade_id smallint,
  unidade_nome text,
  unidade_exibicao text,
  conta_deposito_id smallint,
  conferencia_deposito_desde date,
  deposito_descricao_padrao text,
  fuso_horario text,
  atualizado_em timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem ver a configuracao operacional.';
  end if;
  return query
  select c.unidade_principal_id, u.nome, c.unidade_exibicao, c.conta_deposito_id,
         c.conferencia_deposito_desde, c.deposito_descricao_padrao,
         c.fuso_horario, c.atualizado_em
  from public.configuracao_operacional c
  join public.unidade u on u.id = c.unidade_principal_id
  where c.singleton = true;
end;
$$;

create or replace function public.admin_salvar_configuracao_operacional(
  p_unidade_id smallint,
  p_unidade_exibicao text,
  p_conta_deposito_id smallint,
  p_conferencia_deposito_desde date,
  p_deposito_descricao_padrao text,
  p_fuso_horario text
)
returns public.configuracao_operacional
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_anterior public.configuracao_operacional;
  v_nova public.configuracao_operacional;
  v_unidade text;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem alterar a configuracao operacional.';
  end if;
  select u.nome into v_unidade from public.unidade u where u.id = p_unidade_id;
  if v_unidade is null then
    raise exception using errcode = '22023', message = 'Unidade principal invalida.';
  end if;
  if char_length(btrim(coalesce(p_unidade_exibicao, ''))) not between 1 and 80 then
    raise exception using errcode = '22023', message = 'Nome exibido da unidade invalido.';
  end if;
  if p_conta_deposito_id is not null and not exists (
    select 1 from public.conta c where c.id = p_conta_deposito_id
  ) then
    raise exception using errcode = '22023', message = 'Conta de deposito invalida.';
  end if;
  if p_conferencia_deposito_desde is null then
    raise exception using errcode = '22023', message = 'Informe a data inicial da conferencia.';
  end if;
  if btrim(coalesce(p_deposito_descricao_padrao, '')) = '' then
    raise exception using errcode = '22023', message = 'Informe o padrao do lancamento de deposito.';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = p_fuso_horario) then
    raise exception using errcode = '22023', message = 'Fuso horario invalido.';
  end if;

  select * into v_anterior from public.configuracao_operacional where singleton for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Configuracao operacional nao inicializada.';
  end if;
  if p_unidade_id <> v_anterior.unidade_principal_id then
    raise exception using errcode = '22023',
      message = 'A unidade tecnica da instalacao e unica e nao pode ser trocada.';
  end if;

  update public.configuracao_operacional c
     set unidade_principal_id = p_unidade_id,
         unidade_exibicao = btrim(p_unidade_exibicao),
         conta_deposito_id = p_conta_deposito_id,
         conferencia_deposito_desde = p_conferencia_deposito_desde,
         deposito_descricao_padrao = btrim(p_deposito_descricao_padrao),
         fuso_horario = p_fuso_horario,
         atualizado_por = auth.uid(),
         atualizado_em = now()
   where c.singleton
   returning * into v_nova;

  update public.unidade set ativa = (id = p_unidade_id);
  update public.conta set unidade_id = p_unidade_id;
  update public.venda_especie set unidade = v_unidade where unidade is distinct from v_unidade;
  update public.conta_recorrente set unidade = v_unidade where unidade is distinct from v_unidade;

  if to_jsonb(v_anterior) is distinct from to_jsonb(v_nova) then
    insert into private.configuracao_operacional_historico (
      configuracao_anterior, configuracao_nova, alterado_por
    ) values (to_jsonb(v_anterior), to_jsonb(v_nova), auth.uid());
  end if;
  return v_nova;
end;
$$;

revoke all privileges on function public.unidade_principal_nome() from public, anon, authenticated;
grant execute on function public.unidade_principal_nome() to anon, authenticated;
revoke all privileges on function public.app_configuracao_operacional() from public, anon, authenticated;
grant execute on function public.app_configuracao_operacional() to anon, authenticated;
revoke all privileges on function public.admin_obter_configuracao_operacional() from public, anon, authenticated;
grant execute on function public.admin_obter_configuracao_operacional() to authenticated;
revoke all privileges on function public.admin_salvar_configuracao_operacional(smallint, text, smallint, date, text, text) from public, anon, authenticated;
grant execute on function public.admin_salvar_configuracao_operacional(smallint, text, smallint, date, text, text) to authenticated;

do $validacao$
begin
  if exists (
    select 1 from public.venda_especie v
    where upper(v.unidade) <> upper(public.unidade_principal_nome())
  ) then
    raise exception 'Existem vendas em especie fora da unidade principal; consolidacao cancelada para preservar os numeros.';
  end if;
end;
$validacao$;

-- Converte o estado atual para uma unidade: contas continuam separadas, mas
-- todas pertencem a unidade principal.
update public.unidade u
set ativa = (u.id = (select c.unidade_principal_id from public.configuracao_operacional c where c.singleton));

update public.conta c
set unidade_id = (select o.unidade_principal_id from public.configuracao_operacional o where o.singleton)
where c.unidade_id is distinct from (
  select o.unidade_principal_id from public.configuracao_operacional o where o.singleton
);

update public.venda_especie v
set unidade = public.unidade_principal_nome()
where v.unidade is distinct from public.unidade_principal_nome();

update public.conta_recorrente c
set unidade = public.unidade_principal_nome()
where c.unidade is distinct from public.unidade_principal_nome();

-- ---------------------------------------------------------------------------
-- Fontes financeiras e contas Stone
-- ---------------------------------------------------------------------------

create table if not exists public.fonte_financeira (
  chave text primary key check (chave ~ '^[a-z][a-z0-9_]*$'),
  nome text not null,
  conta_id smallint references public.conta(id),
  ativa boolean not null default true,
  entra_faturamento boolean not null default false,
  entra_caixa boolean not null default true,
  entra_caixa_historico boolean not null default false,
  entra_dre boolean not null default true,
  atualizado_por uuid,
  atualizado_em timestamptz not null default now()
);

alter table public.fonte_financeira
  add column if not exists entra_caixa_historico boolean not null default false;

insert into public.fonte_financeira (
  chave, nome, conta_id, ativa, entra_faturamento, entra_caixa,
  entra_caixa_historico, entra_dre
) values
  ('stone_extrato', 'Extrato Stone', (select id from public.conta where nome = 'Stone' order by id limit 1), true, false, true, false, true),
  ('stone_vendas', 'Vendas Stone', (select id from public.conta where nome = 'Stone' order by id limit 1), true, true, false, false, false),
  ('stone_recebiveis', 'Recebiveis Stone', (select id from public.conta where nome = 'Stone' order by id limit 1), true, false, false, false, false),
  ('venda_especie', 'Venda em especie', null, true, true, true, false, true),
  ('bb', 'Banco do Brasil', (select id from public.conta where nome = 'Banco do Brasil' order by id limit 1), true, false, true, true, true),
  ('bb_pix_qr', 'Pix QR Code', (select id from public.conta where nome = 'Banco do Brasil' order by id limit 1), true, true, false, false, false),
  ('bs_cash', 'BS Cash', (select id from public.conta where nome = 'BS Cash' order by id limit 1), true, false, false, false, true),
  ('inter', 'Inter', (select id from public.conta where nome = 'Inter' order by id limit 1), true, false, true, false, true),
  ('fundopay', 'Fundopay', (select id from public.conta where nome = 'Fundopay' order by id limit 1), true, true, false, false, false)
on conflict (chave) do nothing;

create table if not exists public.stone_conta (
  stonecode text primary key,
  conta_id smallint not null references public.conta(id),
  descricao text,
  ativa boolean not null default true,
  entra_faturamento boolean not null default true,
  atualizado_por uuid,
  atualizado_em timestamptz not null default now()
);

create table if not exists private.fonte_financeira_historico (
  id bigint generated always as identity primary key,
  chave text not null,
  configuracao_anterior jsonb not null,
  configuracao_nova jsonb not null,
  alterado_por uuid,
  alterado_em timestamptz not null default now()
);

create table if not exists private.stone_conta_historico (
  id bigint generated always as identity primary key,
  stonecode text not null,
  configuracao_anterior jsonb not null,
  configuracao_nova jsonb not null,
  alterado_por uuid,
  alterado_em timestamptz not null default now()
);

-- Evita novos avisos de FK sem indice e deixa a manutencao dos vinculos
-- Stone proporcional ao codigo/conta afetado, nao ao tamanho das tabelas raw.
create index if not exists ix_config_operacional_unidade_principal
  on public.configuracao_operacional (unidade_principal_id);
create index if not exists ix_config_operacional_conta_deposito
  on public.configuracao_operacional (conta_deposito_id);
create index if not exists ix_fonte_financeira_conta
  on public.fonte_financeira (conta_id);
create index if not exists ix_stone_conta_conta
  on public.stone_conta (conta_id);
create index if not exists ix_raw_stone_vendas_stonecode
  on public.raw_stone_vendas (stonecode) where stonecode is not null;
create index if not exists ix_raw_stone_vendas_n_serie
  on public.raw_stone_vendas (n_serie) where n_serie is not null;
create index if not exists ix_raw_stone_vendas_conta
  on public.raw_stone_vendas (conta_id);
create index if not exists ix_raw_stone_recebiveis_stonecode
  on public.raw_stone_recebiveis (stonecode) where stonecode is not null;
create index if not exists ix_raw_stone_recebiveis_conta
  on public.raw_stone_recebiveis (conta_id);

-- Contas distintas preservam a origem das cargas antigas. Elas pertencem a
-- mesma unidade e deixam de representar estabelecimentos/unidades separados.
insert into public.conta (nome, banco, unidade_id, ativa)
select distinct
  'Stone - ' || initcap(lower(e.unidade)),
  'Stone',
  o.unidade_principal_id,
  true
from public.stone_estabelecimento e
cross join public.configuracao_operacional o
where o.singleton
  and upper(e.unidade) <> upper(public.unidade_principal_nome())
on conflict (nome) do update
set banco = excluded.banco,
    unidade_id = excluded.unidade_id,
    ativa = true;

insert into public.stone_conta (
  stonecode, conta_id, descricao, ativa, entra_faturamento
)
select
  e.stonecode,
  case
    when upper(e.unidade) = upper(public.unidade_principal_nome())
      then (select c.id from public.conta c where c.nome = 'Stone' order by c.id limit 1)
    else (select c.id from public.conta c where c.nome = 'Stone - ' || initcap(lower(e.unidade)) order by c.id limit 1)
  end,
  coalesce(nullif(e.descricao, ''), 'Conta Stone'),
  true,
  upper(e.unidade) = upper(public.unidade_principal_nome())
from public.stone_estabelecimento e
on conflict (stonecode) do nothing;

alter table public.fonte_financeira enable row level security;
alter table public.stone_conta enable row level security;
alter table private.fonte_financeira_historico enable row level security;
alter table private.stone_conta_historico enable row level security;
revoke all privileges on table public.fonte_financeira from public, anon, authenticated;
revoke all privileges on table public.stone_conta from public, anon, authenticated;
revoke all privileges on table private.fonte_financeira_historico from public, anon, authenticated;
revoke all privileges on table private.stone_conta_historico from public, anon, authenticated;

create or replace function public.admin_listar_fonte_financeira()
returns setof public.fonte_financeira
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  return query select f.* from public.fonte_financeira f order by f.nome;
end;
$$;

create or replace function public.admin_salvar_fonte_financeira(
  p_chave text, p_nome text, p_conta_id smallint, p_ativa boolean,
  p_entra_faturamento boolean, p_entra_caixa boolean,
  p_entra_caixa_historico boolean, p_entra_dre boolean
)
returns public.fonte_financeira
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $$
declare
  v_anterior public.fonte_financeira;
  v public.fonte_financeira;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  if btrim(coalesce(p_nome, '')) = '' then
    raise exception using errcode = '22023', message = 'Nome da fonte obrigatorio.';
  end if;
  if p_conta_id is not null and not exists (
    select 1 from public.conta c where c.id = p_conta_id and c.ativa
  ) then
    raise exception using errcode = '22023', message = 'Conta padrao invalida ou inativa.';
  end if;
  select * into v_anterior
  from public.fonte_financeira f
  where f.chave = p_chave
  for update;
  if not found then
    raise exception using errcode = '22023', message = 'Fonte desconhecida.';
  end if;
  update public.fonte_financeira f
     set nome = btrim(p_nome), conta_id = p_conta_id,
         ativa = coalesce(p_ativa, true),
         entra_faturamento = coalesce(p_entra_faturamento, false),
         entra_caixa = coalesce(p_entra_caixa, false),
         entra_caixa_historico = coalesce(p_entra_caixa_historico, false),
         entra_dre = coalesce(p_entra_dre, false),
         atualizado_por = auth.uid(), atualizado_em = now()
   where f.chave = p_chave
   returning * into v;
  if to_jsonb(v_anterior) is distinct from to_jsonb(v) then
    insert into private.fonte_financeira_historico (
      chave, configuracao_anterior, configuracao_nova, alterado_por
    ) values (v.chave, to_jsonb(v_anterior), to_jsonb(v), auth.uid());
  end if;
  return v;
end;
$$;

create or replace function public.admin_listar_stone_conta()
returns setof public.stone_conta
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  return query select s.* from public.stone_conta s order by s.stonecode;
end;
$$;

create or replace function public.admin_salvar_stone_conta(
  p_stonecode text, p_conta_id smallint, p_descricao text,
  p_ativa boolean, p_entra_faturamento boolean
)
returns public.stone_conta
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $$
declare
  v_anterior public.stone_conta;
  v public.stone_conta;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  if btrim(coalesce(p_stonecode, '')) !~ '^[0-9]+$' then
    raise exception using errcode = '22023', message = 'Codigo Stone invalido.';
  end if;
  if not exists (select 1 from public.conta c where c.id = p_conta_id and c.ativa) then
    raise exception using errcode = '22023', message = 'Conta Stone invalida ou inativa.';
  end if;
  select * into v_anterior
  from public.stone_conta s
  where s.stonecode = btrim(p_stonecode)
  for update;
  insert into public.stone_conta (
    stonecode, conta_id, descricao, ativa, entra_faturamento, atualizado_por
  ) values (
    btrim(p_stonecode), p_conta_id, nullif(btrim(p_descricao), ''),
    coalesce(p_ativa, true), coalesce(p_entra_faturamento, true), auth.uid()
  )
  on conflict (stonecode) do update
  set conta_id = excluded.conta_id, descricao = excluded.descricao,
      ativa = excluded.ativa, entra_faturamento = excluded.entra_faturamento,
      atualizado_por = excluded.atualizado_por, atualizado_em = now()
  returning * into v;

  update public.raw_stone_vendas r
  set conta_id = v.conta_id
  where r.stonecode = v.stonecode
    and r.conta_id is distinct from v.conta_id;
  update public.raw_stone_recebiveis r
  set conta_id = v.conta_id
  where r.stonecode = v.stonecode
    and r.conta_id is distinct from v.conta_id;

  if to_jsonb(v_anterior) is distinct from to_jsonb(v) then
    insert into private.stone_conta_historico (
      stonecode, configuracao_anterior, configuracao_nova, alterado_por
    ) values (
      v.stonecode, coalesce(to_jsonb(v_anterior), 'null'::jsonb),
      to_jsonb(v), auth.uid()
    );
  end if;
  return v;
end;
$$;

revoke all privileges on function public.admin_listar_fonte_financeira() from public, anon, authenticated;
grant execute on function public.admin_listar_fonte_financeira() to authenticated;
revoke all privileges on function public.admin_salvar_fonte_financeira(text, text, smallint, boolean, boolean, boolean, boolean, boolean) from public, anon, authenticated;
grant execute on function public.admin_salvar_fonte_financeira(text, text, smallint, boolean, boolean, boolean, boolean, boolean) to authenticated;
revoke all privileges on function public.admin_listar_stone_conta() from public, anon, authenticated;
grant execute on function public.admin_listar_stone_conta() to authenticated;
revoke all privileges on function public.admin_salvar_stone_conta(text, smallint, text, boolean, boolean) from public, anon, authenticated;
grant execute on function public.admin_salvar_stone_conta(text, smallint, text, boolean, boolean) to authenticated;

-- Ajusta a conta das linhas existentes e futuras sem alterar valor ou chave de
-- deduplicacao. Pix sem stonecode usa o mapa conhecido do terminal.
update public.raw_stone_vendas v
set conta_id = s.conta_id
from public.stone_conta s
where s.stonecode = v.stonecode
  and v.conta_id is distinct from s.conta_id;

with terminal as (
  select v.n_serie, min(v.stonecode) as stonecode
  from public.raw_stone_vendas v
  where v.n_serie is not null and v.stonecode is not null
  group by v.n_serie
)
update public.raw_stone_vendas v
set conta_id = s.conta_id
from terminal t
join public.stone_conta s on s.stonecode = t.stonecode
where v.stonecode is null and v.n_serie = t.n_serie
  and v.conta_id is distinct from s.conta_id;

update public.raw_stone_recebiveis r
set conta_id = s.conta_id
from public.stone_conta s
where s.stonecode = r.stonecode
  and r.conta_id is distinct from s.conta_id;

create or replace function private.definir_conta_stone()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare v_conta smallint; v_serie text := nullif(to_jsonb(new) ->> 'n_serie', '');
begin
  if new.stonecode is not null then
    select s.conta_id into v_conta
    from public.stone_conta s
    where s.stonecode = new.stonecode and s.ativa;
  end if;
  if v_conta is null and tg_table_name = 'raw_stone_vendas' and v_serie is not null then
    select s.conta_id into v_conta
    from public.raw_stone_vendas v
    join public.stone_conta s on s.stonecode = v.stonecode and s.ativa
    where v.n_serie = v_serie
    order by v.id desc limit 1;
  end if;
  new.conta_id := coalesce(v_conta, new.conta_id);
  return new;
end;
$$;

revoke all privileges on function private.definir_conta_stone()
  from public, anon, authenticated;

drop trigger if exists definir_conta_stone_vendas on public.raw_stone_vendas;
create trigger definir_conta_stone_vendas
before insert or update of stonecode, n_serie on public.raw_stone_vendas
for each row execute function private.definir_conta_stone();

drop trigger if exists definir_conta_stone_recebiveis on public.raw_stone_recebiveis;
create trigger definir_conta_stone_recebiveis
before insert or update of stonecode on public.raw_stone_recebiveis
for each row execute function private.definir_conta_stone();

comment on table public.configuracao_operacional is
  'Configuracao singleton da empresa de unidade unica e da conferencia de depositos.';
comment on table public.fonte_financeira is
  'Fontes habilitadas, conta padrao e participacao em faturamento, caixa e DRE.';
comment on table public.stone_conta is
  'Mapa de codigo de origem Stone para conta bancaria da unidade unica.';
comment on table private.migracao_unidade_unica_backup_20260818 is
  'Snapshot anterior a consolidacao, limitado a identificadores e vinculos alterados pela migration.';

commit;
