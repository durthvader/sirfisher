-- Parametriza tolerancia e janelas da conciliacao contabil/estornos.
-- A materialized view preserva colunas, indices, seguranca e defaults atuais.

begin;

-- A view pode estar defasada em relacao aos fatos entre dois refreshes.
-- Recalcula a regra vigente na mesma transacao para que a validacao abaixo
-- compare regras equivalentes, e nao o estado antigo armazenado com dados novos.
set local statement_timeout = 0;
refresh materialized view public.mv_conciliacao_contabil;

drop table if exists pg_temp.p2_antes_conciliacao;
create temporary table p2_antes_conciliacao on commit drop as
select to_jsonb(c) - 'atualizado_em' as linha
from public.mv_conciliacao_contabil c;

drop view if exists public.app_conciliacao_contabil_resumo_mensal;
drop view if exists public.app_conciliacao_contabil;
drop materialized view if exists public.mv_conciliacao_contabil;

create materialized view public.mv_conciliacao_contabil as
with cfg as materialized (
  select
    public.parametro_valor('conciliacao_tolerancia_valor', 0.01) as tolerancia,
    greatest(0, public.parametro_valor('conciliacao_janela_dias', 5)::integer) as conciliacao_dias,
    greatest(0, public.parametro_valor('estorno_janela_dias', 1)::integer) as estorno_dias,
    greatest(0, public.parametro_valor('estorno_forte_minutos', 60)) as estorno_minutos
), fatos as materialized (
  select
    f.origem,
    f.raw_id,
    f.empresa,
    f.data_caixa,
    case
      when f.origem = 'stone_extrato' then se.data_hora
      when f.origem = 'bs_cash' then bc.data_hora
      when f.origem = 'historico' then rh.data_hora
      else null
    end as data_hora,
    f.valor,
    f.tipo,
    f.categoria,
    f.dre_grupo,
    f.contraparte_nome,
    f.contraparte_doc,
    f.fornecedor,
    nullif(public.so_digitos(f.contraparte_doc), '') as contraparte_doc_normalizado,
    nullif(public.normaliza_nome(f.contraparte_nome), '') as contraparte_nome_normalizado,
    lower(coalesce(f.tipo, '') || ' ' || coalesce(f.contraparte_nome, ''))
      ~ '(estorn|devolv|rejeit|cancel)' as tem_indicio_textual
  from public.fato_financeiro f
  left join public.raw_stone_extrato se
    on f.origem = 'stone_extrato' and se.id = f.raw_id
  left join public.raw_bs_cash bc
    on f.origem = 'bs_cash' and bc.id = f.raw_id
  left join public.raw_historico rh
    on f.origem = 'historico' and rh.id = f.raw_id
), pares_reversao_base as (
  select
    d.origem as debito_origem,
    d.raw_id as debito_raw_id,
    c.origem as credito_origem,
    c.raw_id as credito_raw_id,
    d.data_hora as debito_data_hora,
    c.data_hora as credito_data_hora,
    case
      when d.data_hora is not null and c.data_hora is not null
        then extract(epoch from (c.data_hora - d.data_hora)) / 60.0
      else null
    end as minutos_intervalo,
    (
      (d.contraparte_doc_normalizado is not null
       and c.contraparte_doc_normalizado is not null
       and d.contraparte_doc_normalizado = c.contraparte_doc_normalizado)
      or
      (d.contraparte_nome_normalizado is not null
       and c.contraparte_nome_normalizado is not null
       and d.contraparte_nome_normalizado = c.contraparte_nome_normalizado)
    ) as contraparte_confere,
    (d.tem_indicio_textual or c.tem_indicio_textual) as tem_indicio_textual,
    count(*) over (partition by d.origem, d.raw_id)::integer as qtd_para_debito,
    count(*) over (partition by c.origem, c.raw_id)::integer as qtd_para_credito,
    row_number() over (
      partition by d.origem, d.raw_id
      order by
        case when d.tem_indicio_textual or c.tem_indicio_textual then 0 else 1 end,
        case
          when d.contraparte_doc_normalizado is not null
           and d.contraparte_doc_normalizado = c.contraparte_doc_normalizado then 0
          when d.contraparte_nome_normalizado is not null
           and d.contraparte_nome_normalizado = c.contraparte_nome_normalizado then 1
          else 2
        end,
        coalesce(c.data_hora - d.data_hora, interval '1 day'),
        c.raw_id
    ) as ordem_debito,
    row_number() over (
      partition by c.origem, c.raw_id
      order by
        case when d.tem_indicio_textual or c.tem_indicio_textual then 0 else 1 end,
        case
          when d.contraparte_doc_normalizado is not null
           and d.contraparte_doc_normalizado = c.contraparte_doc_normalizado then 0
          when d.contraparte_nome_normalizado is not null
           and d.contraparte_nome_normalizado = c.contraparte_nome_normalizado then 1
          else 2
        end,
        coalesce(c.data_hora - d.data_hora, interval '1 day'),
        d.raw_id
    ) as ordem_credito
  from fatos d
  cross join cfg
  join fatos c
    on c.origem = d.origem
   and c.empresa = d.empresa
   and d.valor < 0
   and c.valor > 0
   and abs(abs(d.valor) - abs(c.valor)) <= cfg.tolerancia
   and c.data_caixa = d.data_caixa
   and (
     d.data_hora is null or c.data_hora is null
     or c.data_hora between d.data_hora
       and d.data_hora + make_interval(days => cfg.estorno_dias)
   )
), pares_reversao as (
  select p.*,
    case
      when p.qtd_para_debito = 1 and p.qtd_para_credito = 1
       and (p.contraparte_confere or p.tem_indicio_textual)
       and p.minutos_intervalo between 0 and cfg.estorno_minutos then 'forte'
      when p.qtd_para_debito = 1 and p.qtd_para_credito = 1
       and (p.contraparte_confere or p.tem_indicio_textual) then 'provavel'
      else 'analise'
    end as nivel_reversao,
    case
      when p.qtd_para_debito > 1 or p.qtd_para_credito > 1
        then 'Mais de um par com o mesmo valor no dia'
      when p.contraparte_confere and p.tem_indicio_textual
        then 'Contraparte confere e o banco indica estorno/devolucao'
      when p.contraparte_confere
        then 'Mesma contraparte, mesmo valor e movimento oposto'
      when p.tem_indicio_textual
        then 'Descricao bancaria indica estorno/devolucao'
      else 'Mesmo valor e movimento oposto no mesmo dia'
    end as evidencia_reversao
  from pares_reversao_base p
  cross join cfg
  where p.ordem_debito = 1 and p.ordem_credito = 1
), reversoes_por_perna as (
  select p.debito_origem as origem, p.debito_raw_id as raw_id,
         p.credito_origem as par_origem, p.credito_raw_id as par_raw_id,
         p.nivel_reversao, p.evidencia_reversao, p.minutos_intervalo,
         p.contraparte_confere,
         greatest(p.qtd_para_debito, p.qtd_para_credito) as qtd_candidatos
  from pares_reversao p
  union all
  select p.credito_origem, p.credito_raw_id, p.debito_origem, p.debito_raw_id,
         p.nivel_reversao, p.evidencia_reversao, p.minutos_intervalo,
         p.contraparte_confere,
         greatest(p.qtd_para_debito, p.qtd_para_credito)
  from pares_reversao p
), base as (
  select f.*,
    r.nivel_reversao, r.evidencia_reversao, r.minutos_intervalo,
    r.contraparte_confere, r.qtd_candidatos as qtd_candidatos_reversao,
    r.par_origem as reversao_par_origem, r.par_raw_id as reversao_par_raw_id,
    (f.categoria in ('Transferencia entre Contas', 'pagamento devolvido', 'estornado')
     or r.raw_id is not null) as espera_zerar
  from fatos f
  left join reversoes_por_perna r on r.origem = f.origem and r.raw_id = f.raw_id
  where f.categoria in (
      'Transferencia entre Contas', 'pagamento devolvido', 'estornado',
      'Antecipacao de Receita', 'Antecipação de Receita',
      'Deposito Dinheiro', 'Depósito Dinheiro',
      'Cartao BB', 'Cartão BB', 'cartao BNB', 'Cartão BTG',
      'ANALISAR INDIVIDUAL'
    ) or r.raw_id is not null
), candidatos_contabeis as (
  select
    b.origem, b.raw_id,
    x.origem as par_origem, x.raw_id as par_raw_id,
    x.data_caixa as par_data, x.data_hora as par_data_hora,
    x.valor as par_valor, x.categoria as par_categoria,
    x.contraparte_nome as par_contraparte,
    abs(x.data_caixa - b.data_caixa)::integer as dias_diferenca,
    count(*) over (partition by b.origem, b.raw_id)::integer as qtd_candidatos,
    row_number() over (
      partition by b.origem, b.raw_id
      order by abs(x.data_caixa - b.data_caixa),
               case when x.categoria = b.categoria then 0 else 1 end,
               x.origem, x.raw_id
    ) as ordem
  from base b
  cross join cfg
  join fatos x
    on b.espera_zerar
   and sign(x.valor) = -sign(b.valor)
   and abs(abs(x.valor) - abs(b.valor)) <= cfg.tolerancia
   and x.data_caixa between b.data_caixa - cfg.conciliacao_dias
                         and b.data_caixa + cfg.conciliacao_dias
   and (x.origem, x.raw_id) <> (b.origem, b.raw_id)
), principal_contabil as (
  select * from candidatos_contabeis where ordem = 1
), resultado as (
  select b.*,
    p.qtd_candidatos as qtd_candidatos_contabil,
    p.par_origem as contabil_par_origem, p.par_raw_id as contabil_par_raw_id,
    p.par_data as contabil_par_data, p.par_data_hora as contabil_par_data_hora,
    p.par_valor as contabil_par_valor, p.par_categoria as contabil_par_categoria,
    p.par_contraparte as contabil_par_contraparte, p.dias_diferenca,
    rp.data_caixa as reversao_par_data, rp.data_hora as reversao_par_data_hora,
    rp.valor as reversao_par_valor, rp.categoria as reversao_par_categoria,
    rp.contraparte_nome as reversao_par_contraparte
  from base b
  left join principal_contabil p on p.origem = b.origem and p.raw_id = b.raw_id
  left join fatos rp
    on rp.origem = b.reversao_par_origem and rp.raw_id = b.reversao_par_raw_id
)
select
  r.origem, r.raw_id, r.data_caixa, r.data_hora,
  to_char(r.data_caixa, 'YYYY-MM') as ano_mes,
  r.valor, r.tipo, r.categoria, r.dre_grupo,
  r.contraparte_nome, r.fornecedor, r.espera_zerar,
  case
    when r.nivel_reversao = 'forte'
     and coalesce(r.categoria, '') not in ('pagamento devolvido', 'estornado')
      then 'estorno_forte'
    when r.nivel_reversao = 'provavel'
     and coalesce(r.categoria, '') not in ('pagamento devolvido', 'estornado')
      then 'estorno_provavel'
    when r.nivel_reversao = 'analise'
     and coalesce(r.categoria, '') not in ('pagamento devolvido', 'estornado')
      then 'estorno_analise'
    when not r.espera_zerar then 'informativo'
    when r.contabil_par_origem is null then 'sem_contrapartida'
    when r.qtd_candidatos_contabil > 1 then 'ambiguo'
    when r.contabil_par_categoria is distinct from r.categoria
      then 'classificacao_divergente'
    else 'conciliado'
  end as status_conciliacao,
  coalesce(r.qtd_candidatos_reversao, r.qtd_candidatos_contabil, 0) as qtd_candidatos,
  coalesce(r.reversao_par_origem, r.contabil_par_origem) as par_origem,
  coalesce(r.reversao_par_raw_id, r.contabil_par_raw_id) as par_raw_id,
  coalesce(r.reversao_par_data, r.contabil_par_data) as par_data,
  coalesce(r.reversao_par_data_hora, r.contabil_par_data_hora) as par_data_hora,
  coalesce(r.reversao_par_valor, r.contabil_par_valor) as par_valor,
  coalesce(r.reversao_par_categoria, r.contabil_par_categoria) as par_categoria,
  coalesce(r.reversao_par_contraparte, r.contabil_par_contraparte) as par_contraparte,
  r.dias_diferenca, r.nivel_reversao, r.evidencia_reversao,
  round(r.minutos_intervalo::numeric, 1) as minutos_intervalo,
  r.contraparte_confere, (r.data_hora is not null) as possui_horario,
  statement_timestamp() as atualizado_em
from resultado r;

create unique index if not exists ux_mv_conciliacao_contabil_origem_raw
  on public.mv_conciliacao_contabil (origem, raw_id);
create index if not exists ix_mv_conciliacao_contabil_mes_status
  on public.mv_conciliacao_contabil (ano_mes, status_conciliacao);
revoke all on public.mv_conciliacao_contabil from public, anon, authenticated;

create or replace view public.app_conciliacao_contabil
with (security_barrier = true, security_invoker = false) as
select
  origem, raw_id, data_caixa, data_hora, ano_mes, valor, tipo, categoria,
  dre_grupo, contraparte_nome, fornecedor, espera_zerar, status_conciliacao,
  qtd_candidatos, par_origem, par_raw_id, par_data, par_data_hora, par_valor,
  par_categoria, par_contraparte, dias_diferenca, nivel_reversao,
  evidencia_reversao, minutos_intervalo, contraparte_confere, possui_horario,
  atualizado_em
from public.mv_conciliacao_contabil
where public.usuario_pode_acessar_pagina('conciliacao_contabil.html');

create or replace view public.app_conciliacao_contabil_resumo_mensal
with (security_barrier = true, security_invoker = false) as
select ano_mes, status_conciliacao, count(*)::integer as qtd,
       round(sum(valor), 2) as total,
       round(coalesce(sum(valor) filter (where valor > 0), 0), 2) as creditos,
       round(coalesce(sum(valor) filter (where valor < 0), 0), 2) as debitos,
       max(atualizado_em) as atualizado_em
from public.mv_conciliacao_contabil
where public.usuario_pode_acessar_pagina('conciliacao_contabil.html')
group by ano_mes, status_conciliacao;

revoke all on public.app_conciliacao_contabil from public, anon;
revoke all on public.app_conciliacao_contabil_resumo_mensal from public, anon;
grant select on public.app_conciliacao_contabil to authenticated;
grant select on public.app_conciliacao_contabil_resumo_mensal to authenticated;

create or replace function public.refresh_painel()
returns void language plpgsql security definer set search_path = public
as $function$
begin
  set local statement_timeout = 0;
  refresh materialized view concurrently mv_fluxo_caixa_diario;
  refresh materialized view concurrently mv_despesa_mensal;
  refresh materialized view concurrently mv_despesa_diaria;
  refresh materialized view concurrently mv_saldo_caixa_diario_detalhado;
  refresh materialized view concurrently mv_conciliacao_contabil;
end;
$function$;

do $validacao$
begin
  if exists (
    (select linha from pg_temp.p2_antes_conciliacao
     except all
     select to_jsonb(c) - 'atualizado_em' from public.mv_conciliacao_contabil c)
    union all
    (select to_jsonb(c) - 'atualizado_em' from public.mv_conciliacao_contabil c
     except all
     select linha from pg_temp.p2_antes_conciliacao)
  ) then
    raise exception 'Regressao de valores ou classificacao na conciliacao contabil.';
  end if;
end;
$validacao$;

commit;
