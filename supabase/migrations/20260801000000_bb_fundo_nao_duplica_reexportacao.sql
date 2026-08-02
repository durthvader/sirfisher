-- =====================================================================
-- Extrato BB: aplicacao em fundo nao duplica quando o banco muda o rotulo
-- =====================================================================
--
-- PROBLEMA
--   A mesma aplicacao de R$ 5.000 em 27/07/2026 entrou duas vezes em raw_bb:
--   primeiro como "Aplicacao Fundo BB" e, numa reexportacao cinco dias
--   depois, como "BB RF LP Selic". O Banco do Brasil tambem trocou o numero
--   do documento. O hash antigo incluia rotulo e documento, entao tratou a
--   versao consolidada como uma transacao nova.
--
-- SOLUCAO
--   1. Remove somente a versao provisoria do par confirmado em producao.
--   2. Para debitos com esses dois rotulos, usa uma identidade canonica por
--      data e valor. O restante do extrato preserva o hash antigo.
--   3. Recria private.parse_bb para a importacao web usar a mesma regra.
--      O parser tambem exige que saldo anterior + movimentos = saldo final;
--      as linhas de saldo deixam de ser simplesmente descartadas sem prova.
--      Para extratos posteriores ao saldo-base do BB, o fechamento informado
--      tambem precisa bater com o saldo que o painel tera apos a carga.
--   4. Agenda o recalculo do saldo e dos snapshots se a limpeza removeu a
--      linha afetada.
--
-- RISCO
--   Duas aplicacoes legitimas, do mesmo valor e no mesmo dia, passariam a
--   compartilhar a chave. A regra fica restrita a este produto/rotulo e a
--   migration aborta se ja houver mais de uma linha consolidada com a mesma
--   data e valor. Nos dados atuais ha um unico par afetado.
--
-- OBJETOS
--   ~ public.raw_bb (remove 1 duplicata e recalcula hashes do fundo)
--   ~ private.parse_bb(jsonb)
--   + tarefa pontual em private.fila_recalculo_saldo, quando necessario
-- =====================================================================

begin;

do $block$
declare
  v_removidos integer := 0;
begin
  -- Limpeza deliberadamente estreita: apenas o par investigado e confirmado.
  delete from public.raw_bb a
  where a.data = date '2026-07-27'
    and a.valor = -5000.00
    and a.lancamento = 'Aplicação Fundo BB'
    and exists (
      select 1
      from public.raw_bb s
      where s.conta_id = a.conta_id
        and s.data = a.data
        and s.valor = a.valor
        and s.lancamento = 'BB RF LP Selic'
    );
  get diagnostics v_removidos = row_count;

  -- Nao escolher silenciosamente entre duas operacoes potencialmente reais.
  if exists (
    select 1
    from public.raw_bb b
    where b.valor < 0
      and b.lancamento in ('Aplicação Fundo BB', 'BB RF LP Selic')
    group by b.conta_id, b.data, b.valor
    having count(*) > 1
  ) then
    raise exception using errcode = '23505',
      message = 'Ha mais de uma aplicacao BB de mesmo valor no mesmo dia; revise antes de canonizar o hash.';
  end if;

  update public.raw_bb b
  set dedup_hash = md5(
    to_char(b.data, 'YYYY-MM-DD') ||
    '|FUNDO_BB_RF_LP_SELIC|' ||
    to_char(b.valor, 'FM999999999999990.00')
  )
  where b.valor < 0
    and b.lancamento in ('Aplicação Fundo BB', 'BB RF LP Selic')
    and b.dedup_hash is distinct from md5(
      to_char(b.data, 'YYYY-MM-DD') ||
      '|FUNDO_BB_RF_LP_SELIC|' ||
      to_char(b.valor, 'FM999999999999990.00')
    );

  if v_removidos > 0 then
    insert into private.fila_recalculo_saldo (
      chave, data_min, data_max, situacao, mensagem
    ) values (
      'corrige-duplicata-fundo-bb-20260727',
      date '2026-07-27', date '2026-07-27', 'pendente',
      'Recalculo apos remover duplicata de aplicacao do fundo BB.'
    )
    on conflict (chave) do update
      set data_min = excluded.data_min,
          data_max = excluded.data_max,
          situacao = 'pendente',
          iniciado_em = null,
          concluido_em = null,
          mensagem = excluded.mensagem;

    perform cron.schedule(
      'sirfisher-processar-recalculo-saldo',
      '5 seconds',
      'select private.processar_fila_recalculo_saldo();'
    );
  end if;
end;
$block$;

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
      private.parse_valor_br(b.valor_raw) as valor_conv,
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
          coalesce(c.valor_raw, 'None') || '|' ||
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
  'Parser do extrato BB; reconcilia o arquivo e o saldo do painel, e canoniza aplicacao provisoria/BB RF LP Selic.';

commit;
