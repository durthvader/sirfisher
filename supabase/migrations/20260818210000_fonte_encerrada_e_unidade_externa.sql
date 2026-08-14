-- =====================================================================
-- Fonte encerrada e unidades externas fora da DRE
-- =====================================================================
--
-- Três correções que nasceram da mesma raiz: campos que acumularam dois
-- significados.
--
-- (1) FONTE ENCERRADA
--   Inter e Fundopay foram encerrados no banco. O painel de status cobra
--   carga por fonte e a única forma de calar o alerta seria desmarcar
--   `ativa` -- mas `ativa` também é o que decide se a fonte entra no caixa
--   e na DRE (`caixa_real_diario`, `listar_calendario_financeiro`,
--   `listar_despesas_dia`, `validar_saldo_diario_materializado`). Desativar
--   a Inter apagaria retroativamente 656 lançamentos do caixa e da DRE.
--
--   Coluna nova `encerrada_em`, simétrica a `considerar_desde`: a fonte
--   continua ativa e o histórico continua valendo integralmente; só o
--   monitoramento para de cobrar. As datas usadas são as do último dado
--   importado de cada fonte (Inter 20/06/2026, Fundopay 10/06/2026).
--
-- (2) UNIDADE EXTERNA -- correção financeira de verdade
--   O consolidado histórico classificava a unidade a partir de `empresa`:
--   'PUB' e 'IMPRENSA' viravam unidade própria, o resto virava a unidade do
--   painel. A consolidação de unidade única (20260818000000) passou a
--   sobrescrever isso com `unidade_principal_nome()` para TODA linha,
--   inclusive as que a própria consulta já havia marcado como de outra
--   unidade.
--
--   Efeito: o caixa continuou correto (ele filtra por `empresa`), mas a DRE
--   -- que filtra por `unidade` -- passou a somar o PUB e a Imprensa dentro
--   do resultado da Praia. Medido: R$ 1.262.057,63 de despesa do PUB e
--   R$ 49.024,20 da Imprensa, com pico de 17,3% da despesa de nov/2025. De
--   março/2026 em diante já está limpo, porque não há mais lançamento
--   histórico dessas unidades.
--
--   A projeção de despesa fixa usa a média dos últimos meses fechados
--   (mai/jun/jul de 2026), todos limpos, então Calendário e projeção não
--   mudam.
--
--   Cuidado que motivou a tabela em vez de um filtro direto: no histórico,
--   `empresa` mistura OUTRA UNIDADE (PUB, IMPRENSA) com CONTA DA MESMA
--   UNIDADE (BB, BTG, CART_BB, BNB, MercadoP, Inter). Um filtro genérico do
--   tipo "empresa <> PRAIA" removeria 1.057 despesas legítimas do cartão do
--   BB, 191 do BNB e assim por diante. Por isso a lista é explícita e
--   parametrizável, não uma regra deduzida.
--
-- (3) stone_estabelecimento
--   Substituída por `stone_conta` e sem nenhum consumidor -- nem view, nem
--   função, nem arquivo do projeto. Removida.
--
-- OBJETOS
--   + public.fonte_financeira.encerrada_em          (coluna)
--   + public.unidade_externa                        (tabela nova)
--   ~ public.fato_financeiro                        (unidade deixa de ser achatada)
--   ~ private.ler_status_cargas()                   (situação "encerrada")
--   ~ public.admin_salvar_fonte_financeira_com_vigencia()  (aceita encerrada_em)
--   - public.stone_estabelecimento                  (removida)
--
-- RISCO: médio, e a migration se valida sozinha.
--   - A troca em `fato_financeiro` é textual e exige exatamente uma
--     ocorrência do trecho esperado; qualquer divergência aborta.
--   - A despesa da DRE é medida antes e depois: a diferença tem de ser
--     exatamente PUB + IMPRENSA, mês a mês. Qualquer outro mês que mude
--     aborta a transação inteira.
--   - Nenhuma linha de dado financeiro é apagada. O histórico do PUB e da
--     Imprensa continua no banco, só deixa de ser somado à Praia.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- (1) Fonte encerrada
-- ---------------------------------------------------------------------

do $migration$
begin
  if not exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = 'public.fonte_financeira'::regclass
      and a.attname = 'encerrada_em'
      and not a.attisdropped
  ) then
    alter table public.fonte_financeira add column encerrada_em date;
  end if;
end;
$migration$;

comment on column public.fonte_financeira.encerrada_em is
  'Data em que a fonte deixou de ser movimentada. O histórico continua valendo integralmente; apenas o monitoramento de carga para de cobrar atualização.';

update public.fonte_financeira
   set encerrada_em = date '2026-06-20'
 where chave = 'inter' and encerrada_em is null;

update public.fonte_financeira
   set encerrada_em = date '2026-06-10'
 where chave = 'fundopay' and encerrada_em is null;

-- ---------------------------------------------------------------------
-- (2) Unidades externas ao painel
-- ---------------------------------------------------------------------

create table if not exists public.unidade_externa (
  empresa text primary key,
  descricao text not null,
  ativa boolean not null default true,
  criado_em timestamptz not null default now()
);

comment on table public.unidade_externa is
  'Valores de fato_financeiro.empresa que pertencem a outra unidade de negócio e não podem ser somados ao resultado da unidade do painel. Não confundir com conta da mesma unidade (BB, BTG, cartão): essas ficam de fora desta lista.';

alter table public.unidade_externa enable row level security;

insert into public.unidade_externa (empresa, descricao) values
  ('PUB', 'Sir Fisher PUB'),
  ('IMPRENSA', 'Sir Fisher Imprensa')
on conflict (empresa) do nothing;

-- Medição antes da troca, para provar que só o esperado muda.
create temporary table despesa_dre_antes on commit drop as
select date_trunc('month', f.data_competencia)::date as mes,
       round(sum(abs(f.valor)), 2) as valor
from public.fato_financeiro f
where f.natureza = 'Despesa'
  and f.entra_dre
  and f.unidade = public.unidade_principal_nome()
  and coalesce(f.dre_grupo, '') <> 'CONTABIL'
group by 1;

create temporary table despesa_externa_esperada on commit drop as
select date_trunc('month', f.data_competencia)::date as mes,
       round(sum(abs(f.valor)), 2) as valor
from public.fato_financeiro f
join public.unidade_externa ue
  on ue.ativa and upper(ue.empresa) = upper(f.empresa)
where f.natureza = 'Despesa'
  and f.entra_dre
  and f.origem = 'historico'
  and coalesce(f.dre_grupo, '') <> 'CONTABIL'
group by 1;

-- A unidade volta a ser derivada de `empresa` quando a linha é de outra
-- unidade. Troca textual: reescrever a view inteira à mão seria 18 mil
-- caracteres de risco desnecessário.
do $migration$
declare
  v_def text;
  v_antigo constant text := 'unidade_principal_nome() AS unidade,';
  v_novo constant text :=
    'CASE
                WHEN EXISTS (
                  SELECT 1 FROM public.unidade_externa ue
                  WHERE ue.ativa AND upper(ue.empresa) = upper(b_1.empresa)
                ) THEN upper(b_1.empresa)
                ELSE unidade_principal_nome()
            END AS unidade,';
  v_ocorrencias integer;
begin
  v_def := pg_get_viewdef('public.fato_financeiro'::regclass, true);
  v_def := regexp_replace(v_def, ';[[:space:]]*$', '');

  if position('public.unidade_externa' in v_def) > 0 then
    return;  -- já aplicada
  end if;

  v_ocorrencias :=
    (length(v_def) - length(replace(v_def, v_antigo, ''))) / length(v_antigo);

  if v_ocorrencias <> 1 then
    raise exception
      'Esperava uma ocorrência de "%" em fato_financeiro, encontrei %.',
      v_antigo, v_ocorrencias;
  end if;

  execute 'create or replace view public.fato_financeiro as '
       || replace(v_def, v_antigo, v_novo);
end;
$migration$;

-- ---------------------------------------------------------------------
-- (3) Status de carga reconhece fonte encerrada
-- ---------------------------------------------------------------------

create or replace function private.ler_status_cargas()
returns table (
  fonte text, linhas bigint, periodo_inicio date, periodo_fim date,
  ultima_importacao timestamptz, ultima_carga timestamptz,
  atraso_dias integer, situacao text
)
language sql stable security definer
set search_path = pg_catalog, pg_temp
as $function$
  with cfg as (
    select
      (current_timestamp at time zone c.fuso_horario)::date as hoje,
      greatest(0, public.parametro_valor('carga_dias_em_dia', 2)::integer) as dias_em_dia,
      greatest(
        public.parametro_valor('carga_dias_atencao', 5)::integer,
        public.parametro_valor('carga_dias_em_dia', 2)::integer + 1
      ) as dias_atencao
    from public.configuracao_operacional c
    where c.singleton
  ), bases as (
    select 'stone_extrato'::text chave, 'Extrato Stone'::text fonte_log,
           count(*)::bigint linhas,
           min(e.data_hora)::date periodo_inicio,
           max(e.data_hora)::date periodo_fim,
           max(e.importado_em) ultima_importacao
    from public.raw_stone_extrato e
    union all
    select 'stone_vendas', 'Vendas Stone', count(*)::bigint,
           min(v.data_venda)::date, max(v.data_venda)::date, max(v.importado_em)
    from public.raw_stone_vendas v
    union all
    select 'stone_recebiveis', 'Recebíveis Stone', count(*)::bigint,
           min(coalesce(r.data_vencimento, r.data_venda::date)),
           max(coalesce(r.data_vencimento, r.data_venda::date)), max(r.importado_em)
    from public.raw_stone_recebiveis r
    union all
    select 'bb', 'Extrato BB', count(*)::bigint,
           min(b.data), max(b.data), max(b.importado_em)
    from public.raw_bb b
    union all
    select 'bs_cash', 'Extrato BS Cash', count(*)::bigint,
           min(c.data_hora)::date, max(c.data_hora)::date, max(c.importado_em)
    from public.raw_bs_cash c
    union all
    select 'inter', 'Extrato Inter', count(*)::bigint,
           min(i.data), max(i.data), max(i.importado_em)
    from public.raw_inter i
    union all
    select 'fundopay', 'Vendas Fundopay', count(*)::bigint,
           min(f.data_venda)::date, max(f.data_venda)::date, max(f.importado_em)
    from public.raw_fundopay_vendas f
  ), logs as (
    select l.fontes as fonte_log, max(l.data_hora) as ultima_carga
    from public.log_carga l
    group by l.fontes
  )
  select
    f.nome as fonte,
    b.linhas,
    b.periodo_inicio,
    b.periodo_fim,
    b.ultima_importacao,
    l.ultima_carga,
    -- Fonte encerrada não acumula atraso: não há carga a cobrar.
    case when f.encerrada_em is not null then null
         when b.ultima_importacao is null then null
         else greatest(cfg.hoje - b.ultima_importacao::date, 0) end::integer,
    case
      when f.encerrada_em is not null then 'encerrada'
      when b.ultima_importacao is null then 'sem carga'
      when cfg.hoje - b.ultima_importacao::date <= cfg.dias_em_dia then 'em dia'
      when cfg.hoje - b.ultima_importacao::date <= cfg.dias_atencao then 'atenção'
      else 'atrasada'
    end::text
  from bases b
  join public.fonte_financeira f on f.chave = b.chave and f.ativa
  left join logs l on l.fonte_log = b.fonte_log
  cross join cfg
  where public.usuario_tem_papel(array['admin']::text[])
  order by f.nome;
$function$;

comment on function private.ler_status_cargas() is
  'Situação de carga por fonte; fonte com encerrada_em aparece como encerrada e não acumula atraso.';

-- ---------------------------------------------------------------------
-- (4) RPC de salvar aceita a data de encerramento
-- ---------------------------------------------------------------------

drop function if exists public.admin_salvar_fonte_financeira_com_vigencia(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text, date
);

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
  p_considerar_desde date,
  p_encerrada_em date
)
returns public.fonte_financeira
language plpgsql security definer
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
  if p_encerrada_em is not null
     and p_considerar_desde is not null
     and p_encerrada_em < p_considerar_desde then
    raise exception using errcode = '22023',
      message = 'A data de encerramento não pode ser anterior ao início da vigência.';
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
      select 1 from public.conta c
      where c.id = p_conta_id and c.ativa and c.saldo_metodo <> 'ignorar'
    ) then
      raise exception using errcode = '22023',
        message = 'A conta escolhida precisa ter cálculo de saldo ativo.';
    end if;
    if exists (
      select 1 from public.fonte_financeira f
      where f.chave <> p_chave
        and f.ativa and f.entra_caixa and f.saldo_adaptador = v_adaptador
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
         encerrada_em = p_encerrada_em,
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
    from public.corte_caixa c limit 1;
    perform private.agendar_refresh_painel(
      coalesce(v_dia, current_date), coalesce(v_dia, current_date)
    );
  end if;

  return v;
end;
$function$;

revoke all privileges on function public.admin_salvar_fonte_financeira_com_vigencia(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text, date, date
) from public, anon;
grant execute on function public.admin_salvar_fonte_financeira_com_vigencia(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text, date, date
) to authenticated;

-- ---------------------------------------------------------------------
-- (5) stone_estabelecimento: sem consumidor
-- ---------------------------------------------------------------------

do $migration$
declare
  v_oid oid := to_regclass('public.stone_estabelecimento');
  v_dependentes integer;
  v_funcoes integer;
begin
  if v_oid is null then
    return;
  end if;

  select count(*) into v_dependentes
  from pg_depend d
  join pg_rewrite r on r.oid = d.objid
  join pg_class c on c.oid = r.ev_class
  where d.refobjid = v_oid and c.oid <> v_oid;

  select count(*) into v_funcoes
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prokind = 'f'
    and pg_get_functiondef(p.oid) ~ '\mstone_estabelecimento\M';

  if v_dependentes > 0 or v_funcoes > 0 then
    raise exception
      'stone_estabelecimento ganhou consumidor (views=%, funcoes=%); remoção cancelada.',
      v_dependentes, v_funcoes;
  end if;
end;
$migration$;

drop table if exists public.stone_estabelecimento;

-- ---------------------------------------------------------------------
-- Derivados e prova numérica
-- ---------------------------------------------------------------------

select public.refresh_painel();

do $validacao$
declare
  v_mes date;
  v_antes numeric;
  v_depois numeric;
  v_esperado numeric;
  v_diferenca numeric;
begin
  for v_mes, v_antes in select mes, valor from despesa_dre_antes loop
    select round(sum(abs(f.valor)), 2) into v_depois
    from public.fato_financeiro f
    where f.natureza = 'Despesa'
      and f.entra_dre
      and f.unidade = public.unidade_principal_nome()
      and coalesce(f.dre_grupo, '') <> 'CONTABIL'
      and date_trunc('month', f.data_competencia)::date = v_mes;

    select coalesce(valor, 0) into v_esperado
    from despesa_externa_esperada where mes = v_mes;

    v_diferenca := v_antes - coalesce(v_depois, 0) - coalesce(v_esperado, 0);

    if abs(coalesce(v_diferenca, 0)) > 0.01 then
      raise exception
        'Despesa de % mudou % além do esperado (antes %, depois %, externo %).',
        to_char(v_mes, 'YYYY-MM'), v_diferenca, v_antes, v_depois, v_esperado;
    end if;
  end loop;

  if exists (
    select 1 from public.fato_financeiro f
    where f.unidade <> public.unidade_principal_nome()
      and upper(f.empresa) not in (select upper(empresa) from public.unidade_externa)
  ) then
    raise exception 'Alguma linha saiu da unidade do painel sem estar na lista de unidades externas.';
  end if;

  if not exists (
    select 1 from public.fonte_financeira
    where chave in ('inter', 'fundopay') and encerrada_em is not null
  ) then
    raise exception 'Inter e Fundopay não foram marcadas como encerradas.';
  end if;

  if to_regclass('public.stone_estabelecimento') is not null then
    raise exception 'stone_estabelecimento continua no banco.';
  end if;
end;
$validacao$;

commit;
