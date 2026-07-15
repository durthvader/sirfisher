-- =====================================================================
-- Importacao pela web: tirar o recalculo do caminho da gravacao
-- =====================================================================
--
-- PROBLEMA (medido em producao)
--   A importacao do extrato Stone pela web morria com "canceling statement due
--   to statement timeout". O papel authenticated tem statement_timeout = 8s
--   (rolconfig do Supabase) e a RPC importar_csv_stone fazia, num unico
--   statement: parse + insert + recalcular_saldo_fechamento + log.
--
--   Medicoes:
--     - public.fato_financeiro (view viva) = 1,34s por avaliacao (52k linhas,
--       une raw_historico + raw_stone_extrato/bb/bs_cash e casa com de_para).
--     - public.saldo_mensal_calculado alcanca fato_financeiro por varios
--       caminhos (corte, real_mes, anchor, e as 4 views de projecao), entao
--       recalcular_saldo_fechamento custa ~5-6s SOZINHO, mesmo para 1 mes.
--       Confirmado: explain analyze filtrando um unico mes = 4,9s, com 29 seq
--       scans em raw_stone_extrato/raw_bb. Estreitar a janela NAO ajuda: o
--       custo e fixo, e do recalculo do historico inteiro.
--     - As 62 chamadas historicas de recalcular_saldo_fechamento (feitas pelo
--       script Python, que conecta direto e nao tem timeout) tem media 8,6s.
--
--   Ou seja: o recalculo sozinho ja consome quase todo o orcamento de 8s.
--   Vendas e recebiveis nao passaram por serem leves — passaram raspando
--   (7,7s de 8s). O desenho anterior era fragil para as tres fontes.
--
--   Cuidado para quem for mexer: "set local statement_timeout" DENTRO da
--   funcao NAO adianta. O timer e armado quando o statement de cima comeca;
--   mudar o GUC no meio nao rearma. O refresh_painel() tem essa linha desde
--   20260719000000 e ela nunca fez efeito — ele funciona porque leva ~3,8s,
--   nao porque a linha ajuda.
--
-- SOLUCAO (nao mexe no financeiro; so em quem chama o que)
--   1. importar_csv_stone deixa de recalcular. Ela grava, registra log_carga e
--      devolve o periodo das linhas EFETIVAMENTE inseridas.
--   2. Novo public.solicitar_recalculo_saldo(date, date): o recalculo ganha um
--      statement so seu, com os 8s inteiros para ele.
--   3. A tela chama, ao fim do lote: um recalculo unico cobrindo todos os
--      arquivos e um refresh unico — em vez de um recalculo por arquivo (3
--      arquivos eram 3 recalculos, ~15s jogados fora). Mesma logica que o
--      rodar_importacoes.bat ja usa para o refresh.
--   4. Se nada foi inserido, a tela nao chama recalculo nem refresh: nada
--      mudou. Reimportar um arquivo ja carregado fica instantaneo.
--
--   Isso NAO conserta a causa raiz (o recalculo continua custando ~5-6s por ser
--   recomputado do zero a partir das tabelas brutas). Materializar essa cadeia
--   e um trabalho a parte, com escolha semantica de quais telas passam a ser
--   snapshot e verificacao numero a numero — nao cabia aqui.
--
-- BONUS: parse mais barato
--   parse_valor_br e parse_data_hora_br usavam bloco EXCEPTION. No plpgsql, um
--   bloco EXCEPTION abre uma SUBTRANSACAO por chamada — e isso rodava ate 4x
--   por linha do arquivo (milhares de subtransacoes por importacao). As duas
--   passam a validar com guarda antes de converter, sem EXCEPTION. O
--   comportamento e identico: as guardas foram conferidas contra float() e
--   strptime do Python nos mesmos casos da 20260751000000.
--
-- OBJETOS
--   ~ private.parse_valor_br(text)          (sem EXCEPTION)
--   ~ private.parse_data_hora_br(text)      (sem EXCEPTION)
--   ~ public.importar_csv_stone(text, jsonb, boolean)  (nao recalcula mais)
--   + public.solicitar_recalculo_saldo(date, date)     (nova)
--
-- RISCO: baixo.
--   - Nenhuma view, tabela ou regra financeira e alterada.
--   - recalcular_saldo_fechamento nao muda; so passa a ser chamada de outro
--     lugar. O script Python continua chamando-a como sempre.
--   - O recalculo passa a cobrir o periodo das linhas inseridas, e nao o
--     periodo do arquivo. E mais correto: mes sem linha nova nao muda de saldo,
--     e a funcao recalcula de p_data_min para frente de qualquer jeito.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Parsers sem subtransacao
-- ---------------------------------------------------------------------

-- Guarda no lugar do try/except: o regex aceita exatamente o que o float() do
-- Python e o ::numeric do Postgres aceitam ("5." e ".5" inclusive; "1-2" e
-- "1.2.3" nao). Conferido caso a caso contra parse_valor_brasileiro().
create or replace function private.parse_valor_br(p_texto text)
returns numeric
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_limpo text;
  v_negativo boolean;
begin
  if p_texto is null then
    return null;
  end if;

  v_limpo := regexp_replace(p_texto, '[^0-9,.\-]', '', 'g');
  if v_limpo in ('', '-', '.', ',') then
    return null;
  end if;

  v_negativo := left(v_limpo, 1) = '-';
  v_limpo := ltrim(replace(replace(v_limpo, '.', ''), ',', '.'), '-');

  if v_limpo !~ '^(\d+\.?\d*|\.\d+)$' then
    return null;
  end if;

  return case when v_negativo then - (v_limpo::numeric) else v_limpo::numeric end;
end;
$function$;

-- Mesma ideia: valida ano/mes/dia/hora na mao em vez de deixar o
-- make_timestamp levantar. Com ano >= 1 e mes entre 1 e 12, o make_date do
-- calculo do ultimo dia do mes nunca falha, entao nao sobra nada para o
-- EXCEPTION pegar. Continua recusando o que o strptime recusa: formato errado
-- (regex), 32/01, mes 13, hora 25 e 29/02 em ano nao bissexto.
create or replace function private.parse_data_hora_br(p_texto text)
returns timestamp
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $function$
declare
  m text[];
  v_ano integer;
  v_mes integer;
  v_dia integer;
  v_hora integer;
  v_min integer;
  v_seg integer;
begin
  if p_texto is null then
    return null;
  end if;

  m := regexp_match(
    btrim(p_texto, E' \t\n\r\f\v'),
    '^(\d{1,2})/(\d{1,2})/(\d{4})(?: (\d{1,2}):(\d{2})(?::(\d{2}))?)?$'
  );
  if m is null then
    return null;
  end if;

  v_ano := m[3]::integer;
  v_mes := m[2]::integer;
  v_dia := m[1]::integer;
  v_hora := coalesce(m[4], '0')::integer;
  v_min := coalesce(m[5], '0')::integer;
  v_seg := coalesce(m[6], '0')::integer;

  if v_ano < 1 or v_mes < 1 or v_mes > 12 or v_dia < 1
     or v_hora > 23 or v_min > 59 or v_seg > 59 then
    return null;
  end if;

  -- Ultimo dia do mes (pega 29/02 em ano nao bissexto).
  if v_dia > extract(
       day from (make_date(v_ano, v_mes, 1) + interval '1 month' - interval '1 day')
     )::integer then
    return null;
  end if;

  return make_timestamp(v_ano, v_mes, v_dia, v_hora, v_min, v_seg);
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. Recalculo do saldo com statement proprio
-- ---------------------------------------------------------------------
-- Mesmo gate da importacao: quem pode importar pode recalcular o que importou.
create or replace function public.solicitar_recalculo_saldo(
  p_data_min date,
  p_data_max date default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_mensagem text;
begin
  if not (
    public.usuario_tem_papel(array['admin']::text[])
    or public.usuario_pode_acessar_pagina('importar.html'::text)
  ) then
    raise exception using errcode = '42501',
      message = 'Sem permissão para recalcular o saldo.';
  end if;

  if p_data_min is null then
    raise exception using errcode = '22023',
      message = 'Informe a data inicial do recálculo.';
  end if;

  select r.mensagem into v_mensagem
  from public.recalcular_saldo_fechamento(
    p_data_min, coalesce(p_data_max, p_data_min), 0
  ) r
  limit 1;

  return jsonb_build_object('mensagem', v_mensagem, 'em', clock_timestamp());
end;
$function$;

revoke all privileges on function public.solicitar_recalculo_saldo(date, date)
  from public, anon, authenticated;
grant execute on function public.solicitar_recalculo_saldo(date, date) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Importacao sem recalculo
-- ---------------------------------------------------------------------
create or replace function public.importar_csv_stone(
  p_fonte text,
  p_linhas jsonb,
  p_dry_run boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_conta_id smallint;
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
begin
  if not public.usuario_pode_acessar_pagina('importar.html'::text) then
    raise exception using errcode = '42501',
      message = 'Sem permissão para importar arquivos.';
  end if;

  v_fonte_log := case p_fonte
    when 'stone_extrato' then 'Extrato Stone'
    when 'stone_vendas' then 'Vendas Stone'
    when 'stone_recebiveis' then 'Recebíveis Stone'
  end;
  if v_fonte_log is null then
    raise exception using errcode = '22023',
      message = 'Fonte desconhecida: ' || coalesce(p_fonte, '(nula)');
  end if;

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

  select c.id into v_conta_id from public.conta c where c.nome = 'Stone' limit 1;
  if v_conta_id is null then
    raise exception using errcode = '23503',
      message = 'Conta operacional não cadastrada: Stone';
  end if;

  -- Validacao + periodo do arquivo, numa passada por fonte.
  if p_fonte = 'stone_extrato' then
    select array_agg('linha ' || r.linha || ': ' || r.motivo order by r.linha)
             filter (where r.motivo <> ''),
           min(r.data_ref), max(r.data_ref)
      into v_rejeicoes, v_periodo_inicio, v_periodo_fim
    from private.parse_stone_extrato(p_linhas) r;
  elsif p_fonte = 'stone_vendas' then
    select array_agg('linha ' || r.linha || ': ' || r.motivo order by r.linha)
             filter (where r.motivo <> ''),
           min(r.data_ref), max(r.data_ref)
      into v_rejeicoes, v_periodo_inicio, v_periodo_fim
    from private.parse_stone_vendas(p_linhas) r;
  else
    select array_agg('linha ' || r.linha || ': ' || r.motivo order by r.linha)
             filter (where r.motivo <> ''),
           min(r.data_ref), max(r.data_ref)
      into v_rejeicoes, v_periodo_inicio, v_periodo_fim
    from private.parse_stone_recebiveis(p_linhas) r;
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

  -- Gravacao (ou so contagem, no dry-run). O RETURNING devolve a data de cada
  -- linha nova: e o periodo que precisa de recalculo, e nao o do arquivo.
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

  else
    if p_dry_run then
      select count(*) into v_novos
      from (
        select distinct r.stone_id, r.n_parcela
        from private.parse_stone_recebiveis(p_linhas) r
      ) d
      where not exists (
        select 1 from public.raw_stone_recebiveis x
        where x.stone_id = d.stone_id and x.n_parcela = d.n_parcela
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
        on conflict (stone_id, n_parcela) do nothing
        -- Mesma precedencia de data do 03_importar_recebiveis_stone.py.
        returning coalesce(data_vencimento, data_venda::date, data_vencimento_original) as data_ref
      )
      select count(*)::integer, min(data_ref), max(data_ref)
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
      'periodo_fim', v_periodo_fim
    );
  end if;

  insert into public.log_carga (fontes) values (v_fonte_log);

  -- O recalculo do saldo e o refresh do painel NAO acontecem aqui: cada um
  -- custa alguns segundos e nao caberia junto no statement_timeout de 8s do
  -- authenticated. A tela chama os dois, uma unica vez, ao fim do lote,
  -- usando recalculo_inicio/fim abaixo (null quando nada foi inserido).
  return jsonb_build_object(
    'dry_run', false,
    'fonte', v_fonte_log,
    'linhas', v_total,
    'inseridos', v_inseridos,
    'ignorados', v_total - v_inseridos,
    'periodo_inicio', v_periodo_inicio,
    'periodo_fim', v_periodo_fim,
    'recalculo_inicio', v_recalc_inicio,
    'recalculo_fim', v_recalc_fim
  );
end;
$function$;

revoke all privileges on function public.importar_csv_stone(text, jsonb, boolean)
  from public, anon, authenticated;
grant execute on function public.importar_csv_stone(text, jsonb, boolean) to authenticated;

commit;
