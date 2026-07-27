-- =====================================================================
-- Importacao pela web ganha as duas protecoes que so o Python tinha
-- =====================================================================
--
-- CONTEXTO
--   O usuario passou a usar so a tela `importar.html`; o script Python
--   fica como excecao. Mas as duas protecoes criadas nas 20260780000000 e
--   20260781000000 tinham ficado apenas no Python, o que fazia da web o
--   caminho **menos** protegido dos dois.
--
-- 1. STONE ID EM NOTACAO CIENTIFICA -> REJEICAO
--   Abrir o CSV no Excel converte o ID de 14 digitos para "2,95639E+13",
--   guardando 6 significativos. A perda e irreversivel e a linha nunca
--   mais casa com a venda -- ja entraram 109 registros assim, apagados na
--   20260780000000. Entra na mesma lista de motivos das demais rejeicoes,
--   entao vale a tolerancia zero que a funcao ja aplica: nada e gravado.
--
--   O padrao exige **digito antes do E**, entao nao pega o ID de Pix, que
--   comeca com E seguido de digitos (E2289643120251231...).
--
-- 2. ESTABELECIMENTO DE OUTRA UNIDADE -> AVISO
--   O relatorio da Stone e por estabelecimento e as tres casas do grupo
--   tem stonecodes distintos (ver `stone_estabelecimento`). Importar o
--   arquivo errado mistura o faturamento -- aconteceu em 28/06/2026 e
--   R$ 25.135,94 de Imprensa e PUB contaram como Praia.
--
--   Aqui e **aviso**, nao rejeicao: o arquivo pode estar integro e ser so
--   de outra casa, e as views ja filtram por unidade. Quem decide e quem
--   esta olhando a tela. Stonecode que nao esteja cadastrado tambem
--   aparece, como '(nao cadastrado)' -- e o caso que pegaria uma unidade
--   nova entrando calada.
--
--   O retorno ganha dois campos, no dry-run e na gravacao:
--     estabelecimentos  {stonecode: linhas}   -- sempre, para conferencia
--     outras_unidades   [{stonecode, unidade, linhas}]  -- so o que destoa
--
-- OBJETOS
--   ~ public.importar_csv_stone(text, jsonb, boolean)
--
--   Gerada a partir de `pg_get_functiondef` com substituicao de trechos
--   ancorados, para nao introduzir diferenca por transcricao.
--
-- RISCO: baixo. A contagem de estabelecimento e uma agregacao a mais sobre
--   um parse que ja roda; nenhum dado e alterado.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.importar_csv_stone(p_fonte text, p_linhas jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_conta_id smallint;
  v_conta_nome text;
  v_total integer;
  v_inseridos integer := 0;
  v_novos integer := 0;
  v_periodo_inicio date;
  v_periodo_fim date;
  v_recalc_inicio date;
  v_recalc_fim date;
  v_rejeicoes text[];
  v_qtd integer;
  v_fonte_log text;
  v_estabelecimentos jsonb;
  v_outras jsonb;
begin
  if not public.usuario_pode_acessar_pagina('importar.html'::text) then
    raise exception using errcode = '42501',
      message = 'Sem permissão para importar arquivos.';
  end if;

  -- Strings iguais as do Python: private.ler_status_cargas() casa por igualdade
  -- exata, e qualquer sufixo quebraria a coluna "Log de carga" em silencio.
  v_fonte_log := case p_fonte
    when 'stone_extrato' then 'Extrato Stone'
    when 'stone_vendas' then 'Vendas Stone'
    when 'stone_recebiveis' then 'Recebíveis Stone'
    when 'bb' then 'Extrato BB'
    when 'bs_cash' then 'Extrato BS Cash'
  end;
  if v_fonte_log is null then
    raise exception using errcode = '22023',
      message = 'Fonte desconhecida: ' || coalesce(p_fonte, '(nula)');
  end if;

  v_conta_nome := case p_fonte
    when 'bb' then 'Banco do Brasil'
    when 'bs_cash' then 'BS Cash'
    else 'Stone'
  end;

  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' then
    raise exception using errcode = '22023',
      message = 'Formato inválido: esperado um array de linhas.';
  end if;

  v_total := jsonb_array_length(p_linhas);
  if v_total = 0 then
    raise exception using errcode = '22023',
      message = 'Arquivo sem linhas de dados.';
  end if;
  if v_total > 20000 then
    raise exception using errcode = '22023',
      message = 'Arquivo com ' || v_total || ' linhas excede o limite de 20000 da '
             || 'importação pela web. Use o script local para cargas grandes.';
  end if;

  select c.id into v_conta_id from public.conta c where c.nome = v_conta_nome limit 1;
  if v_conta_id is null then
    raise exception using errcode = '23503',
      message = 'Conta operacional não cadastrada: ' || v_conta_nome;
  end if;

  -- Validacao + periodo, numa passada por fonte. Linhas ignoradas (rodape de
  -- saldo do extrato) ficam fora tanto da rejeicao quanto do periodo.
  if p_fonte = 'stone_extrato' then
    select array_agg('linha ' || r.linha || ': ' || r.motivo order by r.linha)
             filter (where r.motivo <> ''),
           min(r.data_ref), max(r.data_ref)
      into v_rejeicoes, v_periodo_inicio, v_periodo_fim
    from private.parse_stone_extrato(p_linhas) r;
  elsif p_fonte = 'stone_vendas' then
    -- O ID em notacao cientifica vira rejeicao, como no script Python: o
    -- Excel converte o numero de 14 digitos para 6 significativos e a
    -- linha nunca mais casa com a venda. Entram na mesma lista de motivos,
    -- entao valem a tolerancia zero logo abaixo.
    select array_agg('linha ' || r.linha || ': ' ||
             case when r.stone_id ~ '^[0-9]+[.,]?[0-9]*[Ee][+-]?[0-9]+$' then 'STONE ID em notação científica (' || r.stone_id || ') — o arquivo passou pelo Excel e perdeu dígitos; reexporte sem abrir na planilha'
                  else r.motivo end
             order by r.linha)
             filter (where r.motivo <> '' or r.stone_id ~ '^[0-9]+[.,]?[0-9]*[Ee][+-]?[0-9]+$'),
           min(r.data_ref), max(r.data_ref)
      into v_rejeicoes, v_periodo_inicio, v_periodo_fim
    from private.parse_stone_vendas(p_linhas) r;
  elsif p_fonte = 'stone_recebiveis' then
    -- O ID em notacao cientifica vira rejeicao, como no script Python: o
    -- Excel converte o numero de 14 digitos para 6 significativos e a
    -- linha nunca mais casa com a venda. Entram na mesma lista de motivos,
    -- entao valem a tolerancia zero logo abaixo.
    select array_agg('linha ' || r.linha || ': ' ||
             case when r.stone_id ~ '^[0-9]+[.,]?[0-9]*[Ee][+-]?[0-9]+$' then 'STONE ID em notação científica (' || r.stone_id || ') — o arquivo passou pelo Excel e perdeu dígitos; reexporte sem abrir na planilha'
                  else r.motivo end
             order by r.linha)
             filter (where r.motivo <> '' or r.stone_id ~ '^[0-9]+[.,]?[0-9]*[Ee][+-]?[0-9]+$'),
           min(r.data_ref), max(r.data_ref)
      into v_rejeicoes, v_periodo_inicio, v_periodo_fim
    from private.parse_stone_recebiveis(p_linhas) r;
  elsif p_fonte = 'bb' then
    select array_agg('linha ' || r.linha || ': ' || r.motivo order by r.linha)
             filter (where r.motivo <> ''),
           min(r.data_ref) filter (where not r.ignorar),
           max(r.data_ref) filter (where not r.ignorar)
      into v_rejeicoes, v_periodo_inicio, v_periodo_fim
    from private.parse_bb(p_linhas) r;
  else
    select array_agg('linha ' || r.linha || ': ' || r.motivo order by r.linha)
             filter (where r.motivo <> ''),
           min(r.data_ref) filter (where not r.ignorar),
           max(r.data_ref) filter (where not r.ignorar)
      into v_rejeicoes, v_periodo_inicio, v_periodo_fim
    from private.parse_bs_cash(p_linhas) r;
  end if;

  -- Tolerancia zero, igual ao validar_leitura() do Python.
  if v_rejeicoes is not null then
    v_qtd := array_length(v_rejeicoes, 1);
    raise exception using errcode = '22023',
      message = v_qtd || ' linha(s) rejeitada(s); nenhuma gravação foi feita. '
             || array_to_string(v_rejeicoes[1:12], '; ')
             || case when v_qtd > 12
                     then '; e mais ' || (v_qtd - 12) || ' rejeição(ões)'
                     else '' end;
  end if;

  if v_periodo_inicio is null then
    raise exception using errcode = '22023',
      message = 'Nenhuma data válida encontrada para determinar o período.';
  end if;

  -- Estabelecimento do arquivo. O relatorio da Stone e por unidade e as tres
  -- casas do grupo tem stonecodes distintos; importar o arquivo errado mistura
  -- o faturamento (aconteceu em 28/06/2026). As views ja filtram por unidade,
  -- entao aqui e **aviso**, nao rejeicao: o arquivo pode estar certo e ser so
  -- de outra casa. Quem decide e quem esta olhando a tela.
  if p_fonte = 'stone_vendas' then
    select
      jsonb_object_agg(x.codigo, x.linhas),
      coalesce(jsonb_agg(jsonb_build_object(
                 'stonecode', x.codigo,
                 'unidade', coalesce(e.unidade, '(não cadastrado)'),
                 'linhas', x.linhas))
               filter (where x.codigo <> '(sem stonecode / Pix)'
                         and coalesce(e.unidade, '') <> 'PRAIA'),
               '[]'::jsonb)
      into v_estabelecimentos, v_outras
    from (
      select coalesce(nullif(btrim(r.stonecode), ''), '(sem stonecode / Pix)') as codigo,
             count(*) as linhas
      from private.parse_stone_vendas(p_linhas) r
      group by 1
    ) x
    left join public.stone_estabelecimento e on e.stonecode = x.codigo;
  elsif p_fonte = 'stone_recebiveis' then
    select
      jsonb_object_agg(x.codigo, x.linhas),
      coalesce(jsonb_agg(jsonb_build_object(
                 'stonecode', x.codigo,
                 'unidade', coalesce(e.unidade, '(não cadastrado)'),
                 'linhas', x.linhas))
               filter (where x.codigo <> '(sem stonecode / Pix)'
                         and coalesce(e.unidade, '') <> 'PRAIA'),
               '[]'::jsonb)
      into v_estabelecimentos, v_outras
    from (
      select coalesce(nullif(btrim(r.stonecode), ''), '(sem stonecode / Pix)') as codigo,
             count(*) as linhas
      from private.parse_stone_recebiveis(p_linhas) r
      group by 1
    ) x
    left join public.stone_estabelecimento e on e.stonecode = x.codigo;
  end if;

  if p_fonte = 'stone_extrato' then
    if p_dry_run then
      select count(distinct r.dedup_hash) into v_novos
      from private.parse_stone_extrato(p_linhas) r
      where not exists (
        select 1 from public.raw_stone_extrato x where x.dedup_hash = r.dedup_hash
      );
    else
      with novos as (
        insert into public.raw_stone_extrato (
          conta_id, movimentacao, tipo, valor, saldo_antes, saldo_depois, tarifa,
          data_hora, data_hora_raw, horario, situacao, nosso_numero, destino,
          destino_documento, destino_instituicao, destino_agencia, destino_conta,
          origem, origem_documento, origem_instituicao, origem_agencia,
          origem_conta, descricao, origem_carga, dedup_hash
        )
        select
          v_conta_id, r.movimentacao, r.tipo, r.valor, r.saldo_antes, r.saldo_depois,
          r.tarifa, r.data_hora, r.data_raw, r.horario, r.situacao, r.nosso_numero,
          r.destino, r.destino_documento, r.destino_instituicao, r.destino_agencia,
          r.destino_conta, r.origem, r.origem_documento, r.origem_instituicao,
          r.origem_agencia, r.origem_conta, r.descricao, 'stone_extrato', r.dedup_hash
        from private.parse_stone_extrato(p_linhas) r
        on conflict (dedup_hash) do nothing
        returning data_hora
      )
      select count(*)::integer, min(data_hora)::date, max(data_hora)::date
        into v_inseridos, v_recalc_inicio, v_recalc_fim
      from novos;
    end if;

  elsif p_fonte = 'stone_vendas' then
    if p_dry_run then
      select count(distinct r.stone_id) into v_novos
      from private.parse_stone_vendas(p_linhas) r
      where not exists (
        select 1 from public.raw_stone_vendas x where x.stone_id = r.stone_id
      );
    else
      with novos as (
        insert into public.raw_stone_vendas (
          conta_id, documento, stonecode, data_venda, bandeira, produto, stone_id,
          n_parcelas, valor_bruto, valor_liquido, desconto_mdr, desconto_antecipacao,
          desconto_unificado, n_cartao, meio_captura, n_serie, ultimo_status,
          data_ultimo_status
        )
        select
          v_conta_id, r.documento, r.stonecode, r.data_venda, r.bandeira, r.produto,
          r.stone_id, r.n_parcelas, r.valor_bruto, r.valor_liquido, r.desconto_mdr,
          r.desconto_antecipacao, r.desconto_unificado, r.n_cartao, r.meio_captura,
          r.n_serie, r.ultimo_status, r.data_ultimo_status
        from private.parse_stone_vendas(p_linhas) r
        on conflict (stone_id) do nothing
        returning data_venda
      )
      select count(*)::integer, min(data_venda)::date, max(data_venda)::date
        into v_inseridos, v_recalc_inicio, v_recalc_fim
      from novos;
    end if;

  elsif p_fonte = 'stone_recebiveis' then
    if p_dry_run then
      select count(*) into v_novos
      from (
        select distinct r.stone_id, r.n_parcela, r.categoria
        from private.parse_stone_recebiveis(p_linhas) r
      ) d
      where not exists (
        select 1 from public.raw_stone_recebiveis x
        where x.stone_id = d.stone_id
          and x.n_parcela = d.n_parcela
          and x.categoria = d.categoria
      );
    else
      with novos as (
        insert into public.raw_stone_recebiveis (
          conta_id, documento, stonecode, categoria, data_venda, data_vencimento,
          data_vencimento_original, bandeira, produto, stone_id, qtd_parcelas,
          n_parcela, valor_bruto, valor_liquido, desconto_mdr, desconto_antecipacao,
          desconto_unificado, ultimo_status, data_ultimo_status, entradas_brutas,
          saidas_brutas
        )
        select
          v_conta_id, r.documento, r.stonecode, r.categoria, r.data_venda,
          r.data_vencimento, r.data_vencimento_original, r.bandeira, r.produto,
          r.stone_id, r.qtd_parcelas, r.n_parcela, r.valor_bruto, r.valor_liquido,
          r.desconto_mdr, r.desconto_antecipacao, r.desconto_unificado,
          r.ultimo_status, r.data_ultimo_status, r.entradas_brutas, r.saidas_brutas
        from private.parse_stone_recebiveis(p_linhas) r
        on conflict (stone_id, n_parcela, categoria) do nothing
        -- Mesma precedencia de data do 03_importar_recebiveis_stone.py.
        returning coalesce(data_vencimento, data_venda::date, data_vencimento_original) as data_ref
      )
      select count(*)::integer, min(data_ref), max(data_ref)
        into v_inseridos, v_recalc_inicio, v_recalc_fim
      from novos;
    end if;

  elsif p_fonte = 'bb' then
    if p_dry_run then
      select count(distinct r.dedup_hash) into v_novos
      from private.parse_bb(p_linhas) r
      where not r.ignorar
        and not exists (
          select 1 from public.raw_bb x where x.dedup_hash = r.dedup_hash
        );
    else
      with novos as (
        insert into public.raw_bb (
          conta_id, data, data_raw, lancamento, detalhes,
          n_documento, valor, tipo_lancamento, dedup_hash
        )
        select
          v_conta_id, r.data, r.data_raw, r.lancamento, r.detalhes,
          r.n_documento, r.valor, r.tipo_lancamento, r.dedup_hash
        from private.parse_bb(p_linhas) r
        where not r.ignorar
        on conflict (dedup_hash) do nothing
        returning data
      )
      select count(*)::integer, min(data), max(data)
        into v_inseridos, v_recalc_inicio, v_recalc_fim
      from novos;
    end if;

  else
    if p_dry_run then
      select count(distinct r.dedup_hash) into v_novos
      from private.parse_bs_cash(p_linhas) r
      where not r.ignorar
        and not exists (
          select 1 from public.raw_bs_cash x where x.dedup_hash = r.dedup_hash
        );
    else
      with novos as (
        insert into public.raw_bs_cash (
          conta_id, data_hora, data_raw, dcto, operacao,
          historico, favorecido, valor, saldo, dedup_hash
        )
        select
          v_conta_id, r.data_hora, r.data_raw, r.dcto, r.operacao,
          r.historico, r.favorecido, r.valor, r.saldo, r.dedup_hash
        from private.parse_bs_cash(p_linhas) r
        where not r.ignorar
        on conflict (dedup_hash) do nothing
        returning data_hora
      )
      select count(*)::integer, min(data_hora)::date, max(data_hora)::date
        into v_inseridos, v_recalc_inicio, v_recalc_fim
      from novos;
    end if;
  end if;

  if p_dry_run then
    return jsonb_build_object(
      'dry_run', true,
      'fonte', v_fonte_log,
      'linhas', v_total,
      'novas', v_novos,
      'ja_importadas', v_total - v_novos,
      'periodo_inicio', v_periodo_inicio,
      'periodo_fim', v_periodo_fim,
      'estabelecimentos', v_estabelecimentos,
      'outras_unidades', coalesce(v_outras, '[]'::jsonb)
    );
  end if;

  insert into public.log_carga (fontes) values (v_fonte_log);

  -- O recalculo do saldo e o refresh do painel NAO acontecem aqui: cada um
  -- custa alguns segundos e nao caberia junto no statement_timeout de 8s do
  -- authenticated. A tela chama os dois, uma unica vez, ao fim do lote.
  return jsonb_build_object(
    'dry_run', false,
    'fonte', v_fonte_log,
    'linhas', v_total,
    'inseridos', v_inseridos,
    'ignorados', v_total - v_inseridos,
    'periodo_inicio', v_periodo_inicio,
    'periodo_fim', v_periodo_fim,
    'recalculo_inicio', v_recalc_inicio,
    'recalculo_fim', v_recalc_fim,
    'estabelecimentos', v_estabelecimentos,
    'outras_unidades', coalesce(v_outras, '[]'::jsonb)
  );
end;
$function$
;
