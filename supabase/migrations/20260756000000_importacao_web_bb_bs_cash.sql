-- =====================================================================
-- Importacao pela web tambem para BB e BS Cash (importar.html)
-- =====================================================================
--
-- PROBLEMA
--   A importar.html so reconhecia as 3 fontes Stone. Extrato do Banco do
--   Brasil e extrato do BS Cash continuavam presos ao script local (04_ e
--   05_importar_*.py), que exige Python + .env na maquina. Na pratica isso
--   travou a atualizacao do BS Cash: o extrato ficou semanas sem entrar, e a
--   folha do mes ficou incompleta no DRE.
--
-- SOLUCAO
--   Mesmo desenho da 20260751000000: o navegador so le o CSV e manda as linhas
--   como array de objetos; validacao, conversao, dedup e log ficam no banco.
--   A RPC public.importar_csv_stone ganha as fontes 'bb' e 'bs_cash'.
--
--   O NOME da RPC continua importar_csv_stone (agora um nome historico, ja que
--   trata 5 fontes). Renomear exigiria dropar e recriar, e a pagina (GitHub
--   Pages) e o banco (integracao Supabase) publicam em momentos diferentes —
--   uma janela com pagina nova e banco velho, ou o contrario, quebraria a
--   importacao. Manter o nome deixa as duas pontas compativeis nos dois
--   sentidos.
--
-- ESPELHO DA LOGICA PYTHON (pontos que exigiram cuidado)
--   - dedup_hash: igual ao caso Stone, e md5 de uma f-string do Python, e
--     f-string de None vira o literal "None". Dai o coalesce(campo,'None').
--     Divergiu um caractere, o mesmo arquivo duplica entre os dois caminhos.
--       BB      : data_raw|lancamento|n_documento|valor_raw|detalhes
--       BS Cash : data_raw|dcto|operacao|valor_raw|favorecido
--   - BS Cash junta as colunas de credito e debito: no Python
--     "valor_raw = creditos_raw or debitos_raw". Como campo() ja devolveu null
--     para vazio, o "or" equivale a coalesce() — e o valor_raw que entra no
--     hash e o texto ORIGINAL da coluna escolhida, nao o numero convertido.
--   - LINHAS IGNORADAS x REJEITADAS: os dois scripts PULAM certas linhas antes
--     de validar, e linha pulada nunca vira rejeicao. Por isso as funcoes de
--     parse devolvem a coluna "ignorar", e nao so o "motivo":
--       BB      : Lancamento in ('Saldo Anterior','Saldo do dia','S A L D O')
--       BS Cash : linha sem Data (a linha "SALDO ANTERIOR" do extrato)
--     Sem isso, o rodape de saldo do proprio extrato reprovaria o arquivo
--     inteiro (tolerancia a rejeicao e zero).
--   - FORMATOS DE DATA: cada script aceita um conjunto proprio, e strptime e
--     rigido. Nao da para reusar private.parse_data_hora_br (que aceita hora
--     sem segundos): ela seria mais permissiva que o Python e aceitaria linha
--     que o script rejeita. Dai as duas funcoes novas:
--       parse_data_br         -> so "dd/mm/aaaa"                   (BB)
--       parse_data_hora_seg_br-> "dd/mm/aaaa" ou "dd/mm/aaaa HH:MM:SS" (BS Cash)
--     Ambas sem bloco EXCEPTION (que abre subtransacao por chamada, ver
--     20260752000000): validam ano/mes/dia/hora na mao antes de converter.
--   - log_carga.fontes casa por IGUALDADE EXATA em private.ler_status_cargas()
--     ('Extrato BB', 'Extrato BS Cash'). Strings identicas as do Python.
--   - CODIFICACAO (tratada na pagina, nao aqui): o Python le o BB em latin-1 e
--     o BS Cash em utf-8. Como o hash depende do texto exato, a pagina
--     redecodifica o arquivo na codificacao canonica da fonte antes de montar
--     as linhas. Ver o comentario em importar.html.
--
-- O QUE NAO MUDA
--   - As 3 fontes Stone: mesmo caminho, mesmo comportamento.
--   - Os scripts Python seguem funcionando e gravando as mesmas linhas.
--   - on conflict (dedup_hash) do nothing nos dois casos, sobre indices unicos
--     que ja existiam (uq_bb_dedup, uq_bs_cash_dedup): reenviar o mesmo arquivo
--     nao duplica.
--
-- RISCO: baixo.
--   - Nenhuma tabela, view ou regra financeira e alterada; so insert.
--   - Fontes novas nao afetam as antigas (branches separados).
--   - Erro no meio nao deixa carga pela metade: tudo na transacao da RPC.
--
-- OBJETOS
--   + private.parse_data_br(text)                      (nova)
--   + private.parse_data_hora_seg_br(text)             (nova)
--   + private.parse_bb(jsonb)                          (nova)
--   + private.parse_bs_cash(jsonb)                     (nova)
--   ~ public.importar_csv_stone(text, jsonb, boolean)  (aceita 'bb','bs_cash')
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Parsers de data especificos de cada fonte
-- ---------------------------------------------------------------------

-- Equivale a parse_data_formatos(valor, ("%d/%m/%Y",)) do 04_importar_bb.py.
-- So data, sem hora: se vier hora, o strptime do Python recusa, e aqui tambem.
create or replace function private.parse_data_br(p_texto text)
returns date
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $function$
declare
  m text[];
  v_ano integer;
  v_mes integer;
  v_dia integer;
begin
  if p_texto is null then
    return null;
  end if;

  m := regexp_match(btrim(p_texto, E' \t\n\r\f\v'), '^(\d{1,2})/(\d{1,2})/(\d{4})$');
  if m is null then
    return null;
  end if;

  v_dia := m[1]::integer;
  v_mes := m[2]::integer;
  v_ano := m[3]::integer;

  if v_ano < 1 or v_mes < 1 or v_mes > 12 or v_dia < 1 then
    return null;
  end if;
  -- Ultimo dia do mes (pega 29/02 em ano nao bissexto).
  if v_dia > extract(
       day from (make_date(v_ano, v_mes, 1) + interval '1 month' - interval '1 day')
     )::integer then
    return null;
  end if;

  return make_date(v_ano, v_mes, v_dia);
end;
$function$;

-- Equivale a parse_datetime_formatos(valor, ("%d/%m/%Y %H:%M:%S", "%d/%m/%Y"))
-- do 05_importar_bs_cash.py. Note que a hora, quando vem, exige os SEGUNDOS —
-- "15/07/2026 13:45" e recusado pelo Python, entao tem de ser recusado aqui.
create or replace function private.parse_data_hora_seg_br(p_texto text)
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
    '^(\d{1,2})/(\d{1,2})/(\d{4})(?: (\d{1,2}):(\d{2}):(\d{2}))?$'
  );
  if m is null then
    return null;
  end if;

  v_dia := m[1]::integer;
  v_mes := m[2]::integer;
  v_ano := m[3]::integer;
  v_hora := coalesce(m[4], '0')::integer;
  v_min := coalesce(m[5], '0')::integer;
  v_seg := coalesce(m[6], '0')::integer;

  if v_ano < 1 or v_mes < 1 or v_mes > 12 or v_dia < 1
     or v_hora > 23 or v_min > 59 or v_seg > 59 then
    return null;
  end if;
  if v_dia > extract(
       day from (make_date(v_ano, v_mes, 1) + interval '1 month' - interval '1 day')
     )::integer then
    return null;
  end if;

  return make_timestamp(v_ano, v_mes, v_dia, v_hora, v_min, v_seg);
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. Parse por fonte (espelham 04/05_importar_*.py)
-- ---------------------------------------------------------------------
-- Alem de "motivo" (rejeicao), devolvem "ignorar": linha de saldo do proprio
-- extrato, que o Python pula ANTES de validar e nunca reprova o arquivo.

create or replace function private.parse_bb(p_linhas jsonb)
returns table (
  linha integer,
  data date, data_raw text, lancamento text, detalhes text,
  n_documento text, valor numeric, tipo_lancamento text,
  dedup_hash text, data_ref date, motivo text, ignorar boolean
)
language sql
immutable
set search_path = pg_catalog, pg_temp
as $function$
  with base as (
    select
      t.ord::integer as linha,
      private.campo_csv(t.linha_json, 'Data') as data_raw,
      private.campo_csv(t.linha_json, 'Lançamento') as lancamento,
      private.campo_csv(t.linha_json, 'Detalhes') as detalhes,
      private.campo_csv(t.linha_json, 'N° documento') as n_documento,
      private.campo_csv(t.linha_json, 'Valor') as valor_raw,
      private.campo_csv(t.linha_json, 'Tipo Lançamento') as tipo_lancamento
    from jsonb_array_elements(p_linhas) with ordinality as t(linha_json, ord)
  ), conv as (
    select
      b.*,
      private.parse_data_br(b.data_raw) as data_conv,
      private.parse_valor_br(b.valor_raw) as valor_conv,
      -- LINHAS_NAO_TRANSACAO do 04_importar_bb.py. Com lancamento nulo o IN
      -- devolve null; o coalesce reproduz o "None not in set" -> False.
      coalesce(
        b.lancamento in ('Saldo Anterior', 'Saldo do dia', 'S A L D O'),
        false
      ) as eh_saldo
    from base b
  )
  select
    c.linha,
    c.data_conv, c.data_raw, c.lancamento, c.detalhes,
    c.n_documento, c.valor_conv, c.tipo_lancamento,
    -- f-string do Python: None vira o literal "None".
    md5(
      coalesce(c.data_raw, 'None') || '|' ||
      coalesce(c.lancamento, 'None') || '|' ||
      coalesce(c.n_documento, 'None') || '|' ||
      coalesce(c.valor_raw, 'None') || '|' ||
      coalesce(c.detalhes, 'None')
    ) as dedup_hash,
    c.data_conv as data_ref,
    case when c.eh_saldo then ''
         else array_to_string(array_remove(array[
           case when c.data_conv is null then 'data inválida' end,
           case when c.valor_conv is null then 'valor inválido' end,
           case when c.lancamento is null then 'lançamento ausente' end
         ], null), '; ')
    end as motivo,
    c.eh_saldo as ignorar
  from conv c;
$function$;

create or replace function private.parse_bs_cash(p_linhas jsonb)
returns table (
  linha integer,
  data_hora timestamp, data_raw text, dcto text, operacao text,
  historico text, favorecido text, valor numeric, saldo numeric,
  dedup_hash text, data_ref date, motivo text, ignorar boolean
)
language sql
immutable
set search_path = pg_catalog, pg_temp
as $function$
  with base as (
    select
      t.ord::integer as linha,
      private.campo_csv(t.linha_json, 'Data') as data_raw,
      private.campo_csv(t.linha_json, 'Dcto.') as dcto,
      private.campo_csv(t.linha_json, 'Operação') as operacao,
      private.campo_csv(t.linha_json, 'Histórico') as historico,
      private.campo_csv(t.linha_json, 'Favorecido') as favorecido,
      private.campo_csv(t.linha_json, 'Créditos (R$)') as creditos_raw,
      private.campo_csv(t.linha_json, 'Débitos (R$)') as debitos_raw,
      private.campo_csv(t.linha_json, 'Saldo (R$)') as saldo_raw
    from jsonb_array_elements(p_linhas) with ordinality as t(linha_json, ord)
  ), conv as (
    select
      b.*,
      -- Python: "creditos_raw or debitos_raw". campo() ja devolveu null para
      -- vazio, entao o "or" equivale a coalesce. Este texto CRU e o que entra
      -- no hash.
      coalesce(b.creditos_raw, b.debitos_raw) as valor_raw,
      private.parse_data_hora_seg_br(b.data_raw) as data_hora_conv,
      private.parse_valor_br(b.saldo_raw) as saldo_conv
    from base b
  ), conv2 as (
    select c.*, private.parse_valor_br(c.valor_raw) as valor_conv
    from conv c
  )
  select
    c.linha,
    c.data_hora_conv, c.data_raw, c.dcto, c.operacao,
    c.historico, c.favorecido, c.valor_conv, c.saldo_conv,
    md5(
      coalesce(c.data_raw, 'None') || '|' ||
      coalesce(c.dcto, 'None') || '|' ||
      coalesce(c.operacao, 'None') || '|' ||
      coalesce(c.valor_raw, 'None') || '|' ||
      coalesce(c.favorecido, 'None')
    ) as dedup_hash,
    c.data_hora_conv::date as data_ref,
    -- Linha sem Data e a "SALDO ANTERIOR": o Python pula antes de validar.
    case when c.data_raw is null then ''
         else array_to_string(array_remove(array[
           case when c.data_hora_conv is null then 'data inválida' end,
           case when c.valor_conv is null
                then 'valor inválido (sem crédito nem débito)' end
         ], null), '; ')
    end as motivo,
    (c.data_raw is null) as ignorar
  from conv2 c;
$function$;

revoke all privileges on function private.parse_data_br(text) from public, anon, authenticated;
revoke all privileges on function private.parse_data_hora_seg_br(text) from public, anon, authenticated;
revoke all privileges on function private.parse_bb(jsonb) from public, anon, authenticated;
revoke all privileges on function private.parse_bs_cash(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. RPC de importacao com as 5 fontes
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
    select array_agg('linha ' || r.linha || ': ' || r.motivo order by r.linha)
             filter (where r.motivo <> ''),
           min(r.data_ref), max(r.data_ref)
      into v_rejeicoes, v_periodo_inicio, v_periodo_fim
    from private.parse_stone_vendas(p_linhas) r;
  elsif p_fonte = 'stone_recebiveis' then
    select array_agg('linha ' || r.linha || ': ' || r.motivo order by r.linha)
             filter (where r.motivo <> ''),
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
      'periodo_fim', v_periodo_fim
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
    'recalculo_fim', v_recalc_fim
  );
end;
$function$;

revoke all privileges on function public.importar_csv_stone(text, jsonb, boolean)
  from public, anon, authenticated;
grant execute on function public.importar_csv_stone(text, jsonb, boolean) to authenticated;

commit;
