-- =====================================================================
-- Extrato BB: debito sem sinal negativo e hash estavel entre formatos
-- =====================================================================
--
-- PROBLEMA
--   O extrato de agosto/2026 foi recusado com "saldo final nao confere com
--   saldo anterior + movimentos". O arquivo esta certo: o Banco do Brasil
--   mudou o campo Valor. Ate julho o debito vinha "-1.234,56 D"; agora vem
--   "1.234,56 D", sem o sinal. Os parsers tiram o sinal apenas do "-" e
--   descartam o sufixo, entao todo debito virou credito, a soma dos
--   movimentos inflou e a conferencia estourou. A coluna "Tipo Lancamento"
--   nao serve de substituto: no formato novo ela vem "Entrada" ate na saida.
--
--   O dedup_hash agrava o caso. Ele inclui a string crua do valor, entao o
--   mesmo lancamento reexportado no formato novo gera hash diferente e
--   entraria de novo. Nos dois exports de agosto ja ha duas linhas nessa
--   situacao. A canonizacao da aplicacao em fundo (20260801000000) tambem
--   depende de valor < 0, condicao que o formato novo nunca satisfazia.
--
-- SOLUCAO
--   1. private.parse_valor_bb: le o sinal do sufixo C/D quando ele existe e
--      cai no parser comum quando nao existe. Compativel com os dois
--      formatos, porque "-1.234,56 D" ja era negativo.
--   2. private.parse_bb passa a usar esse parser e a montar o hash com o
--      valor normalizado (FM...0.00) no lugar da string crua.
--   3. Recalcula o dedup_hash das linhas ja gravadas em public.raw_bb com a
--      formula nova, senao o historico duplicaria na proxima reexportacao.
--
-- RISCO
--   O item 3 reescreve a chave de deduplicacao de linhas existentes. Nao
--   toca em data, valor, saldo ou conciliacao. O bloco aborta se a formula
--   nova colidir duas linhas distintas; nos dados atuais as 343 linhas
--   continuam com hash unico. O 04_importar_bb.py foi ajustado na mesma
--   mudanca para manter as duas vias de importacao com o mesmo hash.
--
-- OBJETOS
--   + private.parse_valor_bb(text)
--   ~ private.parse_bb(jsonb)
--   ~ public.raw_bb (recalcula dedup_hash; sem alterar valores)
-- =====================================================================

begin;

create or replace function private.parse_valor_bb(p_texto text)
returns numeric
language sql
immutable
set search_path = pg_catalog, pg_temp
as $function$
  select case
    when private.parse_valor_br(p_texto) is null then null
    when upper(right(btrim(p_texto), 1)) = 'C'
      then abs(private.parse_valor_br(p_texto))
    when upper(right(btrim(p_texto), 1)) = 'D'
      then - abs(private.parse_valor_br(p_texto))
    else private.parse_valor_br(p_texto)
  end;
$function$;

revoke all privileges on function private.parse_valor_bb(text)
  from public, anon, authenticated;

comment on function private.parse_valor_bb(text) is
  'Valor do extrato BB: o sinal vem do sufixo C/D, que o banco manda nos dois formatos.';

create or replace function private.parse_bb(p_linhas jsonb)
returns table (
  linha integer,
  data date, data_raw text, lancamento text, detalhes text,
  n_documento text, valor numeric, tipo_lancamento text,
  dedup_hash text, data_ref date, motivo text, ignorar boolean
)
language sql
stable
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
      private.parse_valor_bb(b.valor_raw) as valor_conv,
      coalesce(
        b.lancamento in ('Saldo Anterior', 'Saldo do dia', 'S A L D O'),
        false
      ) as eh_saldo
    from base b
  ), com_hash as (
    select
      c.*,
      case
        when c.valor_conv < 0
         and c.lancamento in ('Aplicação Fundo BB', 'BB RF LP Selic')
        then md5(
          coalesce(to_char(c.data_conv, 'YYYY-MM-DD'), 'None') ||
          '|FUNDO_BB_RF_LP_SELIC|' ||
          coalesce(to_char(c.valor_conv, 'FM999999999999990.00'), 'None')
        )
        else md5(
          coalesce(c.data_raw, 'None') || '|' ||
          coalesce(c.lancamento, 'None') || '|' ||
          coalesce(c.n_documento, 'None') || '|' ||
          coalesce(to_char(c.valor_conv, 'FM999999999999990.00'), 'None') || '|' ||
          coalesce(c.detalhes, 'None')
        )
      end as hash_conv
    from conv c
  ), conferencia as (
    select
      count(*) filter (where h.lancamento = 'Saldo Anterior') as qtd_abertura,
      count(*) filter (where h.lancamento = 'S A L D O') as qtd_fechamento,
      max(h.valor_conv) filter (where h.lancamento = 'Saldo Anterior') as saldo_abertura,
      max(h.valor_conv) filter (where h.lancamento = 'S A L D O') as saldo_fechamento,
      max(h.data_conv) filter (where h.lancamento = 'S A L D O') as data_fechamento,
      sum(h.valor_conv) filter (where not h.eh_saldo) as movimentos,
      min(h.linha) as primeira_linha
    from com_hash h
  ), saldo_base as (
    select si.saldo, si.data_base
    from public.saldo_inicial si
    where lower(si.conta) = 'bb'
    order by si.data_base desc nulls last
    limit 1
  ), novos_arquivo as (
    select distinct on (h.hash_conv)
      h.data_conv, h.valor_conv, h.hash_conv, h.linha
    from com_hash h
    where not h.eh_saldo
      and h.data_conv is not null
      and h.valor_conv is not null
    order by h.hash_conv, h.linha
  ), saldo_reconstruido as (
    select
      sb.data_base,
      sb.saldo
        + coalesce((
            select sum(b.valor)
            from public.raw_bb b
            where b.data > sb.data_base
              and b.data <= x.data_fechamento
          ), 0)
        + coalesce((
            select sum(n.valor_conv)
            from novos_arquivo n
            where n.data_conv > sb.data_base
              and n.data_conv <= x.data_fechamento
              and not exists (
                select 1 from public.raw_bb b where b.dedup_hash = n.hash_conv
              )
          ), 0) as saldo
    from saldo_base sb
    cross join conferencia x
    where x.data_fechamento > sb.data_base
  )
  select
    h.linha,
    h.data_conv, h.data_raw, h.lancamento, h.detalhes,
    h.n_documento, h.valor_conv, h.tipo_lancamento,
    h.hash_conv as dedup_hash,
    h.data_conv as data_ref,
    case
         when h.linha = x.primeira_linha
          and (x.qtd_abertura <> 1 or x.qtd_fechamento <> 1)
           then 'extrato deve conter exatamente um Saldo Anterior e um S A L D O'
         when h.linha = x.primeira_linha
          and (x.saldo_abertura is null or x.saldo_fechamento is null)
           then 'saldo anterior ou saldo final inválido'
         when h.linha = x.primeira_linha
          and abs(x.saldo_abertura + coalesce(x.movimentos, 0) - x.saldo_fechamento) > 0.01
           then 'saldo final não confere com saldo anterior + movimentos'
         when h.linha = x.primeira_linha
          and sr.saldo is not null
          and abs(sr.saldo - x.saldo_fechamento) > 0.01
           then 'saldo final do extrato não confere com o saldo BB reconstruído no painel'
         when h.eh_saldo then ''
         else array_to_string(array_remove(array[
           case when h.data_conv is null then 'data inválida' end,
           case when h.valor_conv is null then 'valor inválido' end,
           case when h.lancamento is null then 'lançamento ausente' end
         ], null), '; ')
    end as motivo,
    h.eh_saldo as ignorar
  from com_hash h
  cross join conferencia x
  left join saldo_reconstruido sr on true;
$function$;

revoke all privileges on function private.parse_bb(jsonb)
  from public, anon, authenticated;

comment on function private.parse_bb(jsonb) is
  'Parser do extrato BB; sinal pelo sufixo C/D, hash pelo valor normalizado, reconcilia arquivo e saldo do painel.';

do $block$
declare
  v_atualizados integer := 0;
begin
  -- Mesma formula do parse_bb, aplicada as linhas ja gravadas.
  drop table if exists pg_temp.tmp_bb_hash;
  create temporary table tmp_bb_hash on commit drop as
  select
    b.id,
    case
      when b.valor < 0
       and b.lancamento in ('Aplicação Fundo BB', 'BB RF LP Selic')
      then md5(
        coalesce(to_char(b.data, 'YYYY-MM-DD'), 'None') ||
        '|FUNDO_BB_RF_LP_SELIC|' ||
        coalesce(to_char(b.valor, 'FM999999999999990.00'), 'None')
      )
      else md5(
        coalesce(b.data_raw, 'None') || '|' ||
        coalesce(b.lancamento, 'None') || '|' ||
        coalesce(b.n_documento, 'None') || '|' ||
        coalesce(to_char(b.valor, 'FM999999999999990.00'), 'None') || '|' ||
        coalesce(b.detalhes, 'None')
      )
    end as hash_novo
  from public.raw_bb b;

  -- Nao reescrever a chave se ela deixar de identificar a linha.
  if exists (
    select 1 from tmp_bb_hash group by hash_novo having count(*) > 1
  ) then
    raise exception using errcode = '23505',
      message = 'Hash normalizado do BB colidiria entre linhas distintas; revise antes de recalcular.';
  end if;

  update public.raw_bb b
  set dedup_hash = t.hash_novo
  from tmp_bb_hash t
  where t.id = b.id
    and b.dedup_hash is distinct from t.hash_novo;
  get diagnostics v_atualizados = row_count;

  raise notice 'raw_bb: % dedup_hash recalculados.', v_atualizados;
end;
$block$;

commit;
