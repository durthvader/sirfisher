-- RPCs operacionais usam a unidade principal e o periodo de media configurado.

begin;

create or replace function public.listar_contas_recorrentes(p_competencia date)
returns table (
  conta_id bigint, nome text, dia_vencimento smallint, categoria text, tipo text,
  unidade text, ativa boolean, incluir_totais boolean, pagamento_id bigint,
  situacao text, valor numeric, conta_bancaria text, data_pagamento date,
  observacao text, media_3 numeric, atualizado_por_nome text,
  atualizado_em timestamptz
)
language plpgsql stable security definer set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('contas_recorrentes.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_competencia is null or p_competencia <> date_trunc('month', p_competencia)::date then
    raise exception using errcode = '22023', message = 'Competencia invalida.';
  end if;

  return query
  select c.id, c.nome, c.dia_vencimento, c.categoria, c.tipo, c.unidade,
    c.ativa, c.incluir_totais, p.id, p.situacao, p.valor, p.conta_bancaria,
    p.data_pagamento, p.observacao, m.media_periodo,
    private.nome_exibicao_usuario(p.atualizado_por), p.atualizado_em
  from public.conta_recorrente c
  left join public.conta_recorrente_pagamento p
    on p.conta_id = c.id and p.competencia = p_competencia
  left join lateral (
    select round(avg(x.valor), 2) as media_periodo
    from (
      select ph.valor
      from public.conta_recorrente_pagamento ph
      where ph.conta_id = c.id and ph.competencia < p_competencia
        and ph.situacao = 'pago' and ph.valor > 0
      order by ph.competencia desc
      limit greatest(1, public.parametro_valor('meses_media_fixa', 3)::integer)
    ) x
  ) m on true
  where c.unidade = public.unidade_principal_nome()
  order by c.dia_vencimento, c.nome;
end;
$function$;

create or replace function public.salvar_conta_recorrente(
  p_id bigint, p_nome text, p_dia_vencimento smallint, p_categoria text,
  p_tipo text default 'despesa', p_unidade text default null,
  p_ativa boolean default true, p_incluir_totais boolean default true
)
returns bigint language plpgsql security definer set search_path = pg_catalog, public
as $function$
declare v_id bigint; v_unidade text := public.unidade_principal_nome();
begin
  if not public.usuario_pode_acessar_pagina('contas_recorrentes.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_nome is null or length(btrim(p_nome)) < 2
     or p_dia_vencimento not between 1 and 31
     or p_categoria not in ('pessoal', 'ocupacao', 'servicos', 'operacao', 'tributos', 'financeiro', 'outros')
     or p_tipo not in ('despesa', 'rotina') then
    raise exception using errcode = '22023', message = 'Dados da conta invalidos.';
  end if;
  if p_unidade is not null and upper(btrim(p_unidade)) <> upper(v_unidade) then
    raise exception using errcode = '22023', message = 'A instalacao aceita somente a unidade principal.';
  end if;

  if p_id is null then
    insert into public.conta_recorrente (
      nome, dia_vencimento, categoria, tipo, unidade, ativa, incluir_totais,
      criado_por, atualizado_por
    ) values (
      btrim(p_nome), p_dia_vencimento, p_categoria, p_tipo, v_unidade,
      coalesce(p_ativa, true), coalesce(p_incluir_totais, true), auth.uid(), auth.uid()
    ) returning id into v_id;
  else
    update public.conta_recorrente
       set nome = btrim(p_nome), dia_vencimento = p_dia_vencimento,
           categoria = p_categoria, tipo = p_tipo, unidade = v_unidade,
           ativa = coalesce(p_ativa, true),
           incluir_totais = coalesce(p_incluir_totais, true),
           atualizado_por = auth.uid(), atualizado_em = now()
     where id = p_id returning id into v_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'Conta nao encontrada.';
    end if;
  end if;
  return v_id;
end;
$function$;

create or replace function public.salvar_sangria(
  p_data date, p_unidade text, p_valor numeric
)
returns bigint language plpgsql security definer set search_path = pg_catalog, public
as $function$
declare v_id bigint; v_usuario uuid := auth.uid(); v_unidade text := public.unidade_principal_nome();
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_data is null or p_valor is null or p_valor < 0 then
    raise exception using errcode = '22023', message = 'Data ou valor invalido.';
  end if;
  if p_unidade is not null and btrim(p_unidade) <> ''
     and upper(btrim(p_unidade)) <> upper(v_unidade) then
    raise exception using errcode = '22023', message = 'A instalacao aceita somente a unidade principal.';
  end if;

  insert into public.venda_especie (data, unidade, valor, cadastrado_por)
  values (p_data, v_unidade, p_valor, v_usuario)
  on conflict (data, unidade) do update
    set valor = excluded.valor,
        cadastrado_por = venda_especie.cadastrado_por
  returning id::bigint into v_id;
  perform private.solicitar_refresh_saldo_caixa_diario_detalhado();
  return v_id;
end;
$function$;

create or replace function public.admin_listar_meta_mensal()
returns setof public.meta_mensal
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $function$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  return query
  select m.*
  from public.meta_mensal m
  where m.unidade = public.unidade_principal_nome()
  order by m.mes desc;
end;
$function$;

create or replace function public.admin_salvar_meta_mensal(
  p_mes date, p_unidade text, p_meta_bruta numeric
)
returns public.meta_mensal
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $function$
declare
  v public.meta_mensal;
  v_mes date;
  v_unidade text := public.unidade_principal_nome();
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  if p_mes is null or p_meta_bruta is null or p_meta_bruta < 0 then
    raise exception using errcode = '22023', message = 'Mes e meta validos sao obrigatorios.';
  end if;
  if p_unidade is not null and btrim(p_unidade) <> ''
     and upper(btrim(p_unidade)) <> upper(v_unidade) then
    raise exception using errcode = '22023', message = 'A instalacao aceita somente a unidade principal.';
  end if;
  v_mes := date_trunc('month', p_mes)::date;
  insert into public.meta_mensal (mes, unidade, meta_bruta)
  values (v_mes, v_unidade, p_meta_bruta)
  on conflict (mes, unidade) do update set meta_bruta = excluded.meta_bruta
  returning * into v;
  return v;
end;
$function$;

create or replace function public.admin_salvar_conta(
  p_id smallint, p_nome text, p_banco text, p_unidade_id smallint, p_ativa boolean
)
returns public.conta
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $function$
declare
  v public.conta;
  v_unidade_id smallint;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  select c.unidade_principal_id into v_unidade_id
  from public.configuracao_operacional c where c.singleton;
  if btrim(coalesce(p_nome, '')) = '' then
    raise exception using errcode = '22023', message = 'Nome obrigatorio.';
  end if;
  if p_unidade_id is not null and p_unidade_id <> v_unidade_id then
    raise exception using errcode = '22023', message = 'A conta deve pertencer a unidade principal.';
  end if;
  if p_id is null then
    insert into public.conta (nome, banco, unidade_id, ativa)
    values (btrim(p_nome), nullif(btrim(p_banco), ''), v_unidade_id, coalesce(p_ativa, true))
    returning * into v;
  else
    update public.conta
       set nome = btrim(p_nome), banco = nullif(btrim(p_banco), ''),
           unidade_id = v_unidade_id, ativa = coalesce(p_ativa, true)
     where id = p_id
     returning * into v;
    if not found then
      raise exception using errcode = '22023', message = 'Conta id desconhecido.';
    end if;
  end if;
  return v;
end;
$function$;

create or replace function public.admin_listar_unidade()
returns setof public.unidade
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $function$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  return query
  select u.*
  from public.unidade u
  join public.configuracao_operacional c on c.unidade_principal_id = u.id
  where c.singleton;
end;
$function$;

create or replace function public.admin_salvar_unidade(
  p_id smallint, p_nome text, p_ativa boolean
)
returns public.unidade
language plpgsql security definer set search_path = pg_catalog, pg_temp
as $function$
declare v public.unidade;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
  select u.* into v
  from public.unidade u
  join public.configuracao_operacional c on c.unidade_principal_id = u.id
  where c.singleton
  for update of u;
  if not found then
    raise exception using errcode = 'P0002', message = 'Unidade principal nao configurada.';
  end if;
  if p_id is null or p_id <> v.id or btrim(coalesce(p_nome, '')) <> v.nome
     or not coalesce(p_ativa, false) then
    raise exception using errcode = '22023',
      message = 'A unidade tecnica e unica e nao pode ser criada, renomeada ou desativada.';
  end if;
  return v;
end;
$function$;

revoke all privileges on function public.listar_contas_recorrentes(date) from public, anon, authenticated;
grant execute on function public.listar_contas_recorrentes(date) to authenticated;
revoke all privileges on function public.salvar_conta_recorrente(bigint, text, smallint, text, text, text, boolean, boolean) from public, anon, authenticated;
grant execute on function public.salvar_conta_recorrente(bigint, text, smallint, text, text, text, boolean, boolean) to authenticated;
revoke all privileges on function public.salvar_sangria(date, text, numeric) from public, anon, authenticated;
grant execute on function public.salvar_sangria(date, text, numeric) to authenticated;
revoke all privileges on function public.admin_listar_meta_mensal() from public, anon, authenticated;
grant execute on function public.admin_listar_meta_mensal() to authenticated;
revoke all privileges on function public.admin_salvar_meta_mensal(date, text, numeric) from public, anon, authenticated;
grant execute on function public.admin_salvar_meta_mensal(date, text, numeric) to authenticated;
revoke all privileges on function public.admin_salvar_conta(smallint, text, text, smallint, boolean) from public, anon, authenticated;
grant execute on function public.admin_salvar_conta(smallint, text, text, smallint, boolean) to authenticated;
revoke all privileges on function public.admin_listar_unidade() from public, anon, authenticated;
grant execute on function public.admin_listar_unidade() to authenticated;
revoke all privileges on function public.admin_salvar_unidade(smallint, text, boolean) from public, anon, authenticated;
grant execute on function public.admin_salvar_unidade(smallint, text, boolean) to authenticated;

commit;
