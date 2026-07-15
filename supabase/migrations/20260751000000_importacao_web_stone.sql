-- =====================================================================
-- Importacao das 3 fontes Stone pela web (importar.html), sem script local
-- =====================================================================
--
-- PROBLEMA
--   Hoje a unica forma de carregar dados e rodar os scripts Python
--   (scripts/importacao/), que exigem Python, requirements.txt e a
--   DATABASE_URL num .env local. Isso prende a atualizacao do painel a uma
--   maquina especifica: nao da para atualizar pelo celular nem de um
--   computador de terceiro. Alem disso a carga fica restrita a quem tem o
--   ambiente montado, quando a operacao quer que qualquer socio autorizado
--   consiga atualizar.
--
-- SOLUCAO
--   RPC public.importar_csv_stone(p_fonte, p_linhas, p_dry_run), chamada por
--   importar.html. O navegador so le o CSV e faz o parse "burro" (texto ->
--   array de objetos por cabecalho); TODA a validacao, conversao, dedup,
--   recalculo e log ficam aqui no banco, que e a autoridade. Assim o caminho
--   web e o caminho Python gravam exatamente as mesmas linhas.
--
--   p_dry_run = true executa parse + validacao + periodo + contagem de linhas
--   novas e retorna o resumo SEM gravar. E o equivalente ao --dry-run do
--   Python e alimenta a tela de conferencia. Como e o mesmo codigo do caminho
--   real, o preview nao pode divergir da gravacao.
--
-- COMPATIBILIDADE COM O CAMINHO PYTHON (pontos que exigiram cuidado)
--   Os equivalentes SQL dos parsers foram conferidos caso a caso contra as
--   funcoes reais de importacao_core.py (20 valores, 13 datas, hashes com e
--   sem campo nulo e com acento). Os pontos nao obvios:
--   - dedup_hash: o extrato Stone deduplica por md5 de uma string montada em
--     Python com f-string. f-string de None vira o literal "None", entao o
--     coalesce(campo, 'None') abaixo NAO e enfeite: sem ele o mesmo arquivo
--     importado pelos dois caminhos geraria hashes diferentes e duplicaria
--     linha. Conferido: md5() do Postgres == hashlib.md5().hexdigest().
--   - campo(): Python faz str(v).strip() e devolve None se sobrar vazio.
--     btrim() do Postgres so tira espaco por padrao, dai o btrim explicito com
--     \t\n\r\f\v — um \t sobrando mudaria o hash.
--   - datas: strptime e rigido. Um regex ancorado faz a guarda do formato e o
--     make_timestamp() recusa o que e impossivel (29/02/2025, 32/01, mes 13,
--     hora 25), levantando 22008 -> exception -> null, igual ao None do Python.
--     Conferido uma a uma. Note o make_timestamp no lugar do to_timestamp: ver
--     o comentario da propria funcao (fuso).
--   - parse_inteiro(): int() do Python aceita sinal explicito ("+2" -> 2), dai
--     o [+-]? no regex.
--   - log_carga.fontes: private.ler_status_cargas() casa a fonte por
--     IGUALDADE EXATA ('Extrato Stone', 'Vendas Stone', 'Recebiveis Stone').
--     Qualquer sufixo (ex.: " (web)") quebraria a coluna "Log de carga" do
--     status.html em silencio. Por isso a string e identica a do Python.
--   - origem_carga do extrato continua 'stone_extrato', igual ao Python, para
--     que linha vinda da web e linha vinda do script sejam indistinguiveis
--     rio abaixo.
--   - tolerancia zero a rejeicao, igual ao Python: se qualquer linha do
--     arquivo for invalida, nada e gravado.
--
-- POR QUE FUNCOES DE PARSE E NAO TEMP TABLE
--   A versao natural seria jogar as linhas parseadas numa temp table e le-la
--   3x (rejeicoes, periodo, insert). Evitado de proposito: plpgsql cacheia
--   plano por sessao e o PostgREST reusa conexao, entao uma temp table criada
--   e dropada a cada chamada e receita conhecida de "relation ... does not
--   exist" na segunda chamada da mesma conexao. As funcoes private.parse_*
--   sao puras, inlinaveis e nao guardam estado entre chamadas.
--
-- PERMISSAO
--   Gate = public.usuario_pode_acessar_pagina('importar.html'), o mesmo padrao
--   de contas_recorrentes (20260722000000): admin sempre; socio/gerente
--   conforme a linha de pagina_permissao, editavel em permissoes.html. A
--   importacao entra como rotina configuravel, nao como tela exclusiva de
--   admin.
--
-- OBJETOS
--   + private.campo_csv(jsonb, text)                  (novo)
--   + private.parse_valor_br(text)                    (novo)
--   + private.parse_data_hora_br(text)                (novo)
--   + private.parse_inteiro_br(text)                  (novo)
--   + private.parse_stone_extrato(jsonb)              (novo)
--   + private.parse_stone_vendas(jsonb)               (novo)
--   + private.parse_stone_recebiveis(jsonb)           (novo)
--   + public.importar_csv_stone(text, jsonb, boolean) (novo)
--   ~ public.solicitar_refresh_painel()               (gate afrouxado, ver abaixo)
--   + pagina_permissao('importar.html')               (seed)
--
-- RISCO: baixo/medio.
--   - Nenhuma tabela e alterada; so insert com on conflict do nothing nas
--     mesmas chaves unicas ja existentes (uq_extrato_dedup, uq_vendas_stoneid,
--     uq_receb_stoneid_parcela). Reenviar o mesmo arquivo nao duplica.
--   - Tudo (insert + recalculo + log) roda na transacao da propria RPC: erro
--     no meio nao deixa carga pela metade.
--   - solicitar_refresh_painel() deixa de ser exclusiva de admin e passa a
--     aceitar tambem quem tem acesso a importar.html. E intencional: sem isso
--     um socio importaria e o painel continuaria velho na tela dele. O
--     status.html (admin-only) nao muda de comportamento.
--   - Limite de 20.000 linhas por chamada como defesa contra payload absurdo;
--     carga diaria fica na casa das centenas. Arquivos historicos gigantes
--     continuam no caminho Python.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Helpers de parse (espelham importacao_core.py)
-- ---------------------------------------------------------------------
-- Puros e sem security definer: existem so para as funcoes abaixo.

-- Equivale a campo(row, chave) do importacao_core.py.
create or replace function private.campo_csv(p_linha jsonb, p_chave text)
returns text
language sql
immutable
set search_path = pg_catalog, pg_temp
as $function$
  select nullif(btrim(p_linha ->> p_chave, E' \t\n\r\f\v'), '');
$function$;

-- Equivale a parse_valor_brasileiro(): "1.234,56" -> 1234.56, "-50,00" -> -50.00.
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

  begin
    return case when v_negativo then - (v_limpo::numeric) else v_limpo::numeric end;
  exception when others then
    -- Python cai no except ValueError e devolve None (ex.: "1-2", "1,2,3").
    return null;
  end;
end;
$function$;

-- Equivale a parse_datetime_formatos() com FORMATOS_DATA das fontes Stone
-- ("%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y") — os tres cabem num
-- regex so, com a parte de hora opcional.
--
-- NAO usar to_timestamp() aqui: ela e STABLE e devolve timestamptz, entao
-- to_timestamp(...)::timestamp faria uma ida-e-volta pelo fuso da sessao para
-- chegar no timestamp sem fuso da coluna. make_timestamp() e IMMUTABLE, ja
-- devolve timestamp sem fuso e nao depende de TimeZone/DateStyle.
--
-- Divisao do trabalho, conferida caso a caso contra o strptime:
--   - o regex ancorado reproduz a rigidez do formato (recusa "15-07-2026",
--     "2026-07-15", "15/07/2026 13:45:30.123");
--   - o make_timestamp recusa o que e sintaticamente valido mas impossivel
--     ("32/01/2026", "15/13/2026", "25:00:00", "29/02/2025"), levantando 22008
--     que cai no exception abaixo -> null, que e o None do Python.
create or replace function private.parse_data_hora_br(p_texto text)
returns timestamp
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $function$
declare
  m text[];
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

  begin
    return make_timestamp(
      m[3]::integer, m[2]::integer, m[1]::integer,
      coalesce(m[4], '0')::integer,
      coalesce(m[5], '0')::integer,
      coalesce(m[6], '0')::double precision
    );
  exception when others then
    return null;
  end;
end;
$function$;

-- Equivale a parse_inteiro(). O espaco em volta ja caiu no campo_csv().
create or replace function private.parse_inteiro_br(p_texto text)
returns integer
language sql
immutable
set search_path = pg_catalog, pg_temp
as $function$
  select case when p_texto ~ '^[+-]?\d+$' then p_texto::integer end;
$function$;

-- ---------------------------------------------------------------------
-- 2. Parse por fonte (espelham 01/02/03_importar_*.py)
-- ---------------------------------------------------------------------
-- Cada uma devolve, por linha: os campos crus, os convertidos, a data de
-- referencia do periodo (data_ref) e o motivo da rejeicao ('' = linha ok).
-- A RPC chama cada uma no maximo 2x (validacao e insert); sao puras, entao
-- nao ha estado entre chamadas.

create or replace function private.parse_stone_extrato(p_linhas jsonb)
returns table (
  linha integer,
  movimentacao text, tipo text, tarifa text, situacao text, nosso_numero text,
  destino text, destino_documento text, destino_instituicao text,
  destino_agencia text, destino_conta text, origem text, origem_documento text,
  origem_instituicao text, origem_agencia text, origem_conta text, descricao text,
  data_raw text, horario text,
  data_hora timestamp, valor numeric, saldo_antes numeric, saldo_depois numeric,
  dedup_hash text, data_ref date, motivo text
)
language sql
immutable
set search_path = pg_catalog, pg_temp
as $function$
  with base as (
    select
      t.ord::integer as linha,
      private.campo_csv(t.linha_json, 'Data') as data_raw,
      private.campo_csv(t.linha_json, 'Horário') as horario,
      private.campo_csv(t.linha_json, 'Valor') as valor_raw,
      private.campo_csv(t.linha_json, 'Saldo antes') as saldo_antes_raw,
      private.campo_csv(t.linha_json, 'Saldo depois') as saldo_depois_raw,
      private.campo_csv(t.linha_json, 'Movimentação') as movimentacao,
      private.campo_csv(t.linha_json, 'Tipo') as tipo,
      private.campo_csv(t.linha_json, 'Tarifa') as tarifa,
      private.campo_csv(t.linha_json, 'Situação') as situacao,
      private.campo_csv(t.linha_json, 'Nosso Número') as nosso_numero,
      private.campo_csv(t.linha_json, 'Destino') as destino,
      private.campo_csv(t.linha_json, 'Destino Documento') as destino_documento,
      private.campo_csv(t.linha_json, 'Destino Instituição') as destino_instituicao,
      private.campo_csv(t.linha_json, 'Destino Agência') as destino_agencia,
      private.campo_csv(t.linha_json, 'Destino Conta') as destino_conta,
      private.campo_csv(t.linha_json, 'Origem') as origem,
      private.campo_csv(t.linha_json, 'Origem Documento') as origem_documento,
      private.campo_csv(t.linha_json, 'Origem Instituição') as origem_instituicao,
      private.campo_csv(t.linha_json, 'Origem Agência') as origem_agencia,
      private.campo_csv(t.linha_json, 'Origem Conta') as origem_conta,
      private.campo_csv(t.linha_json, 'Descrição') as descricao
    from jsonb_array_elements(p_linhas) with ordinality as t(linha_json, ord)
  ), conv as (
    select
      b.*,
      private.parse_data_hora_br(b.data_raw) as data_hora,
      private.parse_valor_br(b.valor_raw) as valor,
      private.parse_valor_br(b.saldo_antes_raw) as saldo_antes,
      private.parse_valor_br(b.saldo_depois_raw) as saldo_depois
    from base b
  )
  select
    c.linha,
    c.movimentacao, c.tipo, c.tarifa, c.situacao, c.nosso_numero,
    c.destino, c.destino_documento, c.destino_instituicao,
    c.destino_agencia, c.destino_conta, c.origem, c.origem_documento,
    c.origem_instituicao, c.origem_agencia, c.origem_conta, c.descricao,
    c.data_raw, c.horario,
    c.data_hora, c.valor, c.saldo_antes, c.saldo_depois,
    -- f-string do Python: None vira o literal "None". Ver cabecalho.
    md5(
      coalesce(c.data_raw, 'None') || '|' ||
      coalesce(c.horario, 'None') || '|' ||
      coalesce(c.valor_raw, 'None') || '|' ||
      coalesce(c.saldo_depois_raw, 'None') || '|' ||
      coalesce(c.destino_documento, 'None')
    ) as dedup_hash,
    c.data_hora::date as data_ref,
    array_to_string(array_remove(array[
      case when c.data_hora is null then 'data inválida' end,
      case when c.valor is null then 'valor inválido' end,
      case when c.movimentacao is null then 'movimentação ausente' end,
      case when c.saldo_antes_raw is not null and c.saldo_antes is null
           then 'saldo antes inválido' end,
      case when c.saldo_depois_raw is not null and c.saldo_depois is null
           then 'saldo depois inválido' end
    ], null), '; ') as motivo
  from conv c;
$function$;

create or replace function private.parse_stone_vendas(p_linhas jsonb)
returns table (
  linha integer,
  documento text, stonecode text, bandeira text, produto text, stone_id text,
  n_cartao text, meio_captura text, n_serie text, ultimo_status text,
  data_venda timestamp, data_ultimo_status timestamp, n_parcelas integer,
  valor_bruto numeric, valor_liquido numeric, desconto_mdr numeric,
  desconto_antecipacao numeric, desconto_unificado numeric,
  data_ref date, motivo text
)
language sql
immutable
set search_path = pg_catalog, pg_temp
as $function$
  with base as (
    select
      t.ord::integer as linha,
      private.campo_csv(t.linha_json, 'STONE ID') as stone_id,
      private.campo_csv(t.linha_json, 'DOCUMENTO') as documento,
      private.campo_csv(t.linha_json, 'STONECODE') as stonecode,
      private.campo_csv(t.linha_json, 'DATA DA VENDA') as data_venda_raw,
      private.campo_csv(t.linha_json, 'BANDEIRA') as bandeira,
      private.campo_csv(t.linha_json, 'PRODUTO') as produto,
      private.campo_csv(t.linha_json, 'N DE PARCELAS') as n_parcelas_raw,
      private.campo_csv(t.linha_json, 'VALOR BRUTO') as valor_bruto_raw,
      private.campo_csv(t.linha_json, 'VALOR LIQUIDO') as valor_liquido_raw,
      private.campo_csv(t.linha_json, 'DESCONTO DE MDR') as desconto_mdr_raw,
      private.campo_csv(t.linha_json, 'DESCONTO DE ANTECIPACAO') as desconto_antecipacao_raw,
      private.campo_csv(t.linha_json, 'DESCONTO UNIFICADO') as desconto_unificado_raw,
      private.campo_csv(t.linha_json, 'N DO CARTAO') as n_cartao,
      private.campo_csv(t.linha_json, 'MEIO DE CAPTURA') as meio_captura,
      private.campo_csv(t.linha_json, 'N DE SERIE') as n_serie,
      private.campo_csv(t.linha_json, 'ULTIMO STATUS') as ultimo_status,
      private.campo_csv(t.linha_json, 'DATA DO ULTIMO STATUS') as data_ultimo_status_raw
    from jsonb_array_elements(p_linhas) with ordinality as t(linha_json, ord)
  ), conv as (
    select
      b.*,
      private.parse_data_hora_br(b.data_venda_raw) as data_venda,
      private.parse_data_hora_br(b.data_ultimo_status_raw) as data_ultimo_status,
      private.parse_inteiro_br(b.n_parcelas_raw) as n_parcelas,
      private.parse_valor_br(b.valor_bruto_raw) as valor_bruto,
      private.parse_valor_br(b.valor_liquido_raw) as valor_liquido,
      private.parse_valor_br(b.desconto_mdr_raw) as desconto_mdr,
      private.parse_valor_br(b.desconto_antecipacao_raw) as desconto_antecipacao,
      private.parse_valor_br(b.desconto_unificado_raw) as desconto_unificado
    from base b
  )
  select
    c.linha,
    c.documento, c.stonecode, c.bandeira, c.produto, c.stone_id,
    c.n_cartao, c.meio_captura, c.n_serie, c.ultimo_status,
    c.data_venda, c.data_ultimo_status, c.n_parcelas,
    c.valor_bruto, c.valor_liquido, c.desconto_mdr,
    c.desconto_antecipacao, c.desconto_unificado,
    c.data_venda::date as data_ref,
    array_to_string(array_remove(array[
      case when c.stone_id is null then 'STONE ID ausente' end,
      case when c.data_venda is null then 'data da venda inválida' end,
      case when c.valor_bruto is null then 'valor bruto inválido' end,
      case when c.valor_liquido is null then 'valor líquido inválido' end,
      case when c.n_parcelas_raw is not null and c.n_parcelas is null
           then 'número de parcelas inválido' end,
      case when c.desconto_mdr_raw is not null and c.desconto_mdr is null
           then 'desconto MDR inválido' end,
      case when c.desconto_antecipacao_raw is not null and c.desconto_antecipacao is null
           then 'desconto de antecipação inválido' end,
      case when c.desconto_unificado_raw is not null and c.desconto_unificado is null
           then 'desconto unificado inválido' end,
      case when c.data_ultimo_status_raw is not null and c.data_ultimo_status is null
           then 'data do último status inválida' end
    ], null), '; ') as motivo
  from conv c;
$function$;

create or replace function private.parse_stone_recebiveis(p_linhas jsonb)
returns table (
  linha integer,
  documento text, stonecode text, categoria text, bandeira text, produto text,
  stone_id text, ultimo_status text,
  data_venda timestamp, data_vencimento date, data_vencimento_original date,
  data_ultimo_status timestamp, qtd_parcelas integer, n_parcela integer,
  valor_bruto numeric, valor_liquido numeric, desconto_mdr numeric,
  desconto_antecipacao numeric, desconto_unificado numeric,
  entradas_brutas numeric, saidas_brutas numeric,
  data_ref date, motivo text
)
language sql
immutable
set search_path = pg_catalog, pg_temp
as $function$
  with base as (
    select
      t.ord::integer as linha,
      private.campo_csv(t.linha_json, 'STONE ID') as stone_id,
      private.campo_csv(t.linha_json, 'DOCUMENTO') as documento,
      private.campo_csv(t.linha_json, 'STONECODE') as stonecode,
      private.campo_csv(t.linha_json, 'CATEGORIA') as categoria,
      private.campo_csv(t.linha_json, 'DATA DA VENDA') as data_venda_raw,
      private.campo_csv(t.linha_json, 'DATA DE VENCIMENTO') as data_vencimento_raw,
      private.campo_csv(t.linha_json, 'DATA DE VENCIMENTO ORIGINAL') as data_vencimento_original_raw,
      private.campo_csv(t.linha_json, 'BANDEIRA') as bandeira,
      private.campo_csv(t.linha_json, 'PRODUTO') as produto,
      private.campo_csv(t.linha_json, 'QTD DE PARCELAS') as qtd_parcelas_raw,
      private.campo_csv(t.linha_json, 'Nº DA PARCELA') as n_parcela_raw,
      private.campo_csv(t.linha_json, 'VALOR BRUTO') as valor_bruto_raw,
      private.campo_csv(t.linha_json, 'VALOR LÍQUIDO') as valor_liquido_raw,
      private.campo_csv(t.linha_json, 'DESCONTO DE MDR') as desconto_mdr_raw,
      private.campo_csv(t.linha_json, 'DESCONTO DE ANTECIPAÇÃO') as desconto_antecipacao_raw,
      private.campo_csv(t.linha_json, 'DESCONTO UNIFICADO') as desconto_unificado_raw,
      private.campo_csv(t.linha_json, 'ÚLTIMO STATUS') as ultimo_status,
      private.campo_csv(t.linha_json, 'DATA DO ÚLTIMO STATUS') as data_ultimo_status_raw,
      private.campo_csv(t.linha_json, 'ENTRADAS BRUTAS') as entradas_brutas_raw,
      private.campo_csv(t.linha_json, 'SAÍDAS BRUTAS') as saidas_brutas_raw
    from jsonb_array_elements(p_linhas) with ordinality as t(linha_json, ord)
  ), conv as (
    select
      b.*,
      private.parse_data_hora_br(b.data_venda_raw) as data_venda,
      -- parse_data_formatos(): mesmo parse, truncado para date.
      private.parse_data_hora_br(b.data_vencimento_raw)::date as data_vencimento,
      private.parse_data_hora_br(b.data_vencimento_original_raw)::date as data_vencimento_original,
      private.parse_data_hora_br(b.data_ultimo_status_raw) as data_ultimo_status,
      private.parse_inteiro_br(b.qtd_parcelas_raw) as qtd_parcelas,
      private.parse_inteiro_br(b.n_parcela_raw) as n_parcela,
      private.parse_valor_br(b.valor_bruto_raw) as valor_bruto,
      private.parse_valor_br(b.valor_liquido_raw) as valor_liquido,
      private.parse_valor_br(b.desconto_mdr_raw) as desconto_mdr,
      private.parse_valor_br(b.desconto_antecipacao_raw) as desconto_antecipacao,
      private.parse_valor_br(b.desconto_unificado_raw) as desconto_unificado,
      private.parse_valor_br(b.entradas_brutas_raw) as entradas_brutas,
      private.parse_valor_br(b.saidas_brutas_raw) as saidas_brutas
    from base b
  )
  select
    c.linha,
    c.documento, c.stonecode, c.categoria, c.bandeira, c.produto,
    c.stone_id, c.ultimo_status,
    c.data_venda, c.data_vencimento, c.data_vencimento_original,
    c.data_ultimo_status, c.qtd_parcelas, c.n_parcela,
    c.valor_bruto, c.valor_liquido, c.desconto_mdr,
    c.desconto_antecipacao, c.desconto_unificado,
    c.entradas_brutas, c.saidas_brutas,
    -- Mesma precedencia do 03_importar_recebiveis_stone.py.
    coalesce(c.data_vencimento, c.data_venda::date, c.data_vencimento_original) as data_ref,
    array_to_string(array_remove(array[
      case when c.stone_id is null then 'STONE ID ausente' end,
      case when c.n_parcela is null then 'número da parcela inválido' end,
      case when c.valor_liquido is null then 'valor líquido inválido' end,
      case when c.data_vencimento is null and c.data_venda is null
                and c.data_vencimento_original is null
           then 'nenhuma data de referência válida' end,
      case when c.data_venda_raw is not null and c.data_venda is null
           then 'data da venda inválida' end,
      case when c.data_vencimento_raw is not null and c.data_vencimento is null
           then 'data de vencimento inválida' end,
      case when c.data_vencimento_original_raw is not null and c.data_vencimento_original is null
           then 'data de vencimento original inválida' end,
      case when c.qtd_parcelas_raw is not null and c.qtd_parcelas is null
           then 'quantidade de parcelas inválida' end,
      case when c.valor_bruto_raw is not null and c.valor_bruto is null
           then 'valor bruto inválido' end,
      case when c.desconto_mdr_raw is not null and c.desconto_mdr is null
           then 'desconto MDR inválido' end,
      case when c.desconto_antecipacao_raw is not null and c.desconto_antecipacao is null
           then 'desconto de antecipação inválido' end,
      case when c.desconto_unificado_raw is not null and c.desconto_unificado is null
           then 'desconto unificado inválido' end,
      case when c.data_ultimo_status_raw is not null and c.data_ultimo_status is null
           then 'data do último status inválida' end,
      case when c.entradas_brutas_raw is not null and c.entradas_brutas is null
           then 'entradas brutas inválidas' end,
      case when c.saidas_brutas_raw is not null and c.saidas_brutas is null
           then 'saídas brutas inválidas' end
    ], null), '; ') as motivo
  from conv c;
$function$;

-- Menor privilegio, como as demais funcoes de private: por padrao o Postgres
-- da EXECUTE a PUBLIC, e authenticated TEM usage no schema private (anon nao).
-- Estas sao chamadas so de dentro da importar_csv_stone, que roda como dona
-- (postgres), entao ninguem mais precisa de execute.
revoke all privileges on function private.campo_csv(jsonb, text) from public, anon, authenticated;
revoke all privileges on function private.parse_valor_br(text) from public, anon, authenticated;
revoke all privileges on function private.parse_data_hora_br(text) from public, anon, authenticated;
revoke all privileges on function private.parse_inteiro_br(text) from public, anon, authenticated;
revoke all privileges on function private.parse_stone_extrato(jsonb) from public, anon, authenticated;
revoke all privileges on function private.parse_stone_vendas(jsonb) from public, anon, authenticated;
revoke all privileges on function private.parse_stone_recebiveis(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. RPC de importacao
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
  v_rejeicoes text[];
  v_qtd integer;
  v_fonte_log text;
begin
  -- Gate: mesma permissao da pagina, editavel em permissoes.html.
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

  -- Mesmo motivo do refresh_painel(): o role authenticated tem timeout curto.
  set local statement_timeout = '120s';

  -- Validacao + periodo numa passada so, por fonte.
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

  -- Gravacao (ou so contagem, no dry-run).
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
        returning 1
      )
      select count(*)::integer into v_inseridos from novos;
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
        returning 1
      )
      select count(*)::integer into v_inseridos from novos;
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
        returning 1
      )
      select count(*)::integer into v_inseridos from novos;
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

  -- Mesma sequencia do importacao_core.importar_registros(): insert, recalculo
  -- e log na mesma transacao. O refresh do painel fica de fora (e caro; a tela
  -- dispara solicitar_refresh_painel() uma unica vez ao fim do lote).
  perform * from public.recalcular_saldo_fechamento(v_periodo_inicio, v_periodo_fim, 0);
  insert into public.log_carga (fontes) values (v_fonte_log);

  return jsonb_build_object(
    'dry_run', false,
    'fonte', v_fonte_log,
    'linhas', v_total,
    'inseridos', v_inseridos,
    'ignorados', v_total - v_inseridos,
    'periodo_inicio', v_periodo_inicio,
    'periodo_fim', v_periodo_fim
  );
end;
$function$;

revoke all privileges on function public.importar_csv_stone(text, jsonb, boolean)
  from public, anon, authenticated;
grant execute on function public.importar_csv_stone(text, jsonb, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Refresh do painel para quem importa
-- ---------------------------------------------------------------------
-- Sem isto, um socio com acesso a importar.html gravaria a carga e continuaria
-- vendo o painel velho: solicitar_refresh_painel() era exclusiva de admin
-- (20260719000000) e refresh_painel() esta revogada de authenticated
-- (20260702210000). O gate passa a aceitar tambem quem pode importar. O
-- status.html continua admin-only e nao muda.
create or replace function public.solicitar_refresh_painel()
returns timestamptz
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $function$
begin
  if not (
    public.usuario_tem_papel(array['admin']::text[])
    or public.usuario_pode_acessar_pagina('importar.html'::text)
  ) then
    raise exception using errcode = '42501',
      message = 'Sem permissão para atualizar o painel.';
  end if;

  perform public.refresh_painel();

  return clock_timestamp();
end;
$function$;

revoke all privileges on function public.solicitar_refresh_painel()
  from public, anon, authenticated;
grant execute on function public.solicitar_refresh_painel() to authenticated;

-- ---------------------------------------------------------------------
-- 5. A rotina entra em permissoes.html
-- ---------------------------------------------------------------------
-- Default socio: admin ja tem acesso irrestrito por fora da tabela, e a
-- intencao e liberar a carga para os socios. Ajustavel em permissoes.html.
insert into public.pagina_permissao (pagina, papeis)
values ('importar.html', array['socio'])
on conflict (pagina) do nothing;

commit;
