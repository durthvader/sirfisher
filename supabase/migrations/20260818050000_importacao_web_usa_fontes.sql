-- A importacao web passa a resolver a conta pelo cadastro de fontes. A
-- substituicao ancorada preserva parsers, deduplicacao e retorno da RPC atual.

do $migration$
declare
  v_def text;
  v_nova text;
  v_assinatura regprocedure := 'public.importar_csv_stone(text,jsonb,boolean)'::regprocedure;
begin
  select pg_get_functiondef(v_assinatura) into v_def;

  if position('from public.fonte_financeira f' in v_def) > 0
     and position('public.stone_conta e' in v_def) > 0 then
    return;
  end if;

  v_nova := replace(
    v_def,
    $old$  v_conta_nome := case p_fonte
    when 'bb' then 'Banco do Brasil'
    when 'bs_cash' then 'BS Cash'
    else 'Stone'
  end;$old$,
    $new$  v_conta_nome := null;$new$
  );

  v_nova := replace(
    v_nova,
    $old$  select c.id into v_conta_id from public.conta c where c.nome = v_conta_nome limit 1;
  if v_conta_id is null then
    raise exception using errcode = '23503',
      message = 'Conta operacional não cadastrada: ' || v_conta_nome;
  end if;$old$,
    $new$  select f.conta_id, c.nome
    into v_conta_id, v_conta_nome
    from public.fonte_financeira f
    left join public.conta c on c.id = f.conta_id
    where f.chave = p_fonte and f.ativa
    limit 1;
  if v_conta_id is null then
    raise exception using errcode = '23503',
      message = 'Fonte sem conta operacional ativa: ' || p_fonte;
  end if;$new$
  );

  v_nova := replace(
    v_nova,
    'left join public.stone_estabelecimento e on e.stonecode = x.codigo',
    'left join public.stone_conta e on e.stonecode = x.codigo'
  );
  v_nova := replace(
    v_nova,
    'coalesce(e.unidade, ''(não cadastrado)'')',
    'coalesce(e.descricao, ''(conta não configurada)'')'
  );
  v_nova := replace(
    v_nova,
    'and coalesce(e.unidade, '''') <> ' || quote_literal('PRA' || 'IA'),
    'and not coalesce(e.ativa, false)'
  );

  if v_nova = v_def
     or position('from public.fonte_financeira f' in v_nova) = 0
     or position('public.stone_conta e' in v_nova) = 0
     or position('stone_estabelecimento' in v_nova) > 0 then
    raise exception 'Definicao inesperada de importar_csv_stone; migracao cancelada.';
  end if;

  execute v_nova;
end;
$migration$;

revoke all privileges on function public.importar_csv_stone(text, jsonb, boolean)
  from public, anon;
grant execute on function public.importar_csv_stone(text, jsonb, boolean)
  to authenticated;
