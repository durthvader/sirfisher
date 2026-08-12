-- Remove do código o corte histórico fixo do BS Cash.
-- A vigência passa a pertencer à configuração de cada fonte. O valor atual
-- do BS Cash é preservado e a comparação integral do fato impede regressão.

begin;

do $migration$
begin
  if not exists (
    select 1
    from pg_catalog.pg_attribute a
    where a.attrelid = 'public.fonte_financeira'::regclass
      and a.attname = 'considerar_desde'
      and not a.attisdropped
  ) then
    alter table public.fonte_financeira
      add column considerar_desde date;

    -- Compatibilidade com o histórico já consolidado nesta instalação.
    -- Em uma instalação neutra o bootstrap pode limpar essa data.
    update public.fonte_financeira
       set considerar_desde = date '2026-01-01'
     where chave = 'bs_cash';
  end if;
end;
$migration$;

comment on column public.fonte_financeira.considerar_desde is
  'Primeiro dia incluído no fato financeiro para a fonte; nulo inclui todo o histórico.';

drop table if exists pg_temp.p3_antes_vigencia_fontes;
create temporary table p3_antes_vigencia_fontes on commit drop as
select to_jsonb(f) as linha
from public.fato_financeiro f;

do $migration$
declare
  v_def text;
  v_sem_corte text;
begin
  select pg_get_viewdef('public.fato_financeiro'::regclass, true)
    into v_def;
  v_def := regexp_replace(v_def, ';[[:space:]]*$', '');

  if position('considerar_desde' in v_def) > 0 then
    return;
  end if;

  -- pg_get_viewdef normaliza DATE '2026-01-01' como '2026-01-01'::date.
  -- O padrão tolera os parênteses que variam entre versões do PostgreSQL.
  v_sem_corte := regexp_replace(
    v_def,
    $regex$[[:space:]]+where[[:space:]]+[(]*c\.data_hora[)]*::date[[:space:]]*>=[[:space:]]*[(]*'2026-01-01'::date[)]*$regex$,
    '',
    'i'
  );

  if v_sem_corte = v_def or position('2026-01-01' in v_sem_corte) > 0 then
    raise exception 'Não foi possível remover com segurança o corte fixo do BS Cash.';
  end if;

  execute 'create or replace view public.fato_financeiro as
    select
      b.origem,
      b.raw_id,
      b.empresa,
      b.data_caixa,
      b.data_competencia,
      b.movimentacao,
      b.tipo,
      b.valor,
      b.contraparte_nome,
      b.contraparte_doc,
      b.fornecedor,
      b.categoria,
      b.dre_grupo,
      b.status,
      b.unidade,
      b.natureza,
      b.entra_dre
    from (' || v_sem_corte || ') b
    left join public.fonte_financeira cfg_vigencia
      on cfg_vigencia.chave = b.origem
    where cfg_vigencia.considerar_desde is null
       or b.data_caixa >= cfg_vigencia.considerar_desde';
end;
$migration$;

do $validacao$
begin
  if exists (
    (select linha from pg_temp.p3_antes_vigencia_fontes
     except all
     select to_jsonb(f) from public.fato_financeiro f)
    union all
    (select to_jsonb(f) from public.fato_financeiro f
     except all
     select linha from pg_temp.p3_antes_vigencia_fontes)
  ) then
    raise exception 'Regressão numérica ou classificatória ao parametrizar a vigência das fontes.';
  end if;
end;
$validacao$;

comment on view public.fato_financeiro is
  'Fato financeiro unificado da unidade principal; participação e vigência respeitam a configuração da fonte.';

create or replace function public.admin_salvar_fonte_financeira_com_vigencia(
  p_chave text,
  p_nome text,
  p_conta_id smallint,
  p_ativa boolean,
  p_entra_faturamento boolean,
  p_entra_caixa boolean,
  p_entra_caixa_historico boolean,
  p_entra_dre boolean,
  p_saldo_adaptador text,
  p_considerar_desde date
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
         considerar_desde = p_considerar_desde,
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

revoke all privileges on function public.admin_salvar_fonte_financeira_com_vigencia(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text, date
) from public, anon, authenticated;
grant execute on function public.admin_salvar_fonte_financeira_com_vigencia(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text, date
) to authenticated;

-- Mantém compatibilidade com clientes que ainda não enviam a vigência.
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
  v_considerar_desde date;
begin
  select f.considerar_desde into v_considerar_desde
  from public.fonte_financeira f
  where f.chave = p_chave;

  return public.admin_salvar_fonte_financeira_com_vigencia(
    p_chave,
    p_nome,
    p_conta_id,
    p_ativa,
    p_entra_faturamento,
    p_entra_caixa,
    p_entra_caixa_historico,
    p_entra_dre,
    p_saldo_adaptador,
    v_considerar_desde
  );
end;
$function$;

revoke all privileges on function public.admin_salvar_fonte_financeira_com_saldo(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text
) from public, anon, authenticated;
grant execute on function public.admin_salvar_fonte_financeira_com_saldo(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text
) to authenticated;

commit;
