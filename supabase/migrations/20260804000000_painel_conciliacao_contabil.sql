-- =====================================================================
-- Painel de rotina para conciliacao de movimentos contabeis
-- =====================================================================
--
-- REGRA DE NEGOCIO
--   Nem toda categoria de natureza Contabil precisa zerar. Transferencias,
--   pagamentos devolvidos e estornos devem ter uma perna oposta. Faturas de
--   cartao, depositos de dinheiro e antecipacoes sao apenas informativos.
--
-- PAREAMENTO
--   Procura movimento de sinal oposto, mesmo valor absoluto (tolerancia de
--   R$ 0,01) e data em uma janela de cinco dias. Um unico candidato com a
--   mesma categoria e conciliado; categoria diferente, varios candidatos ou
--   ausencia de candidato ficam visiveis para revisao. Nada e corrigido aqui.
--
-- OBJETOS
--   + public.mv_conciliacao_contabil
--   + public.app_conciliacao_contabil
--   + public.app_conciliacao_contabil_resumo_mensal
--   ~ public.refresh_painel()
--   + permissao configuravel para conciliacao_contabil.html
-- =====================================================================

begin;

drop view if exists public.app_conciliacao_contabil_resumo_mensal;
drop view if exists public.app_conciliacao_contabil;
drop materialized view if exists public.mv_conciliacao_contabil;

create materialized view public.mv_conciliacao_contabil as
with fatos as materialized (
  select
    f.origem,
    f.raw_id,
    f.data_caixa,
    f.valor,
    f.tipo,
    f.categoria,
    f.dre_grupo,
    f.contraparte_nome,
    f.fornecedor
  from public.fato_financeiro f
),
base as (
  select
    f.*,
    f.categoria in (
      'Transferencia entre Contas',
      'pagamento devolvido',
      'estornado'
    ) as espera_zerar
  from fatos f
  where f.categoria in (
    'Transferencia entre Contas',
    'pagamento devolvido',
    'estornado',
    'Antecipação de Receita',
    'Depósito Dinheiro',
    'Cartão BB',
    'cartão BNB',
    'Cartão BTG',
    'ANALISAR INDIVIDUAL'
  )
),
candidatos as (
  select
    b.origem,
    b.raw_id,
    x.origem as par_origem,
    x.raw_id as par_raw_id,
    x.data_caixa as par_data,
    x.valor as par_valor,
    x.categoria as par_categoria,
    x.contraparte_nome as par_contraparte,
    abs(x.data_caixa - b.data_caixa)::integer as dias_diferenca,
    count(*) over (partition by b.origem, b.raw_id)::integer as qtd_candidatos,
    row_number() over (
      partition by b.origem, b.raw_id
      order by
        abs(x.data_caixa - b.data_caixa),
        case when x.categoria = b.categoria then 0 else 1 end,
        x.origem,
        x.raw_id
    ) as ordem
  from base b
  join fatos x
    on b.espera_zerar
   and sign(x.valor) = -sign(b.valor)
   and abs(abs(x.valor) - abs(b.valor)) <= 0.01
   and x.data_caixa between b.data_caixa - 5 and b.data_caixa + 5
   and (x.origem, x.raw_id) <> (b.origem, b.raw_id)
),
principal as (
  select *
  from candidatos
  where ordem = 1
)
select
  b.origem,
  b.raw_id,
  b.data_caixa,
  to_char(b.data_caixa, 'YYYY-MM') as ano_mes,
  b.valor,
  b.tipo,
  b.categoria,
  b.dre_grupo,
  b.contraparte_nome,
  b.fornecedor,
  b.espera_zerar,
  case
    when not b.espera_zerar then 'informativo'
    when p.par_origem is null then 'sem_contrapartida'
    when p.qtd_candidatos > 1 then 'ambiguo'
    when p.par_categoria is distinct from b.categoria then 'classificacao_divergente'
    else 'conciliado'
  end as status_conciliacao,
  coalesce(p.qtd_candidatos, 0) as qtd_candidatos,
  p.par_origem,
  p.par_raw_id,
  p.par_data,
  p.par_valor,
  p.par_categoria,
  p.par_contraparte,
  p.dias_diferenca,
  statement_timestamp() as atualizado_em
from base b
left join principal p
  on p.origem = b.origem
 and p.raw_id = b.raw_id;

create unique index if not exists ux_mv_conciliacao_contabil_origem_raw
  on public.mv_conciliacao_contabil (origem, raw_id);

create index if not exists ix_mv_conciliacao_contabil_mes_status
  on public.mv_conciliacao_contabil (ano_mes, status_conciliacao);

comment on materialized view public.mv_conciliacao_contabil is
  'Auditoria somente leitura de movimentos contabeis; pareia sinal oposto, mesmo valor e janela de cinco dias sem corrigir classificacoes.';

revoke all on public.mv_conciliacao_contabil from public, anon, authenticated;

create or replace view public.app_conciliacao_contabil
with (security_barrier = true, security_invoker = false) as
select
  origem,
  raw_id,
  data_caixa,
  ano_mes,
  valor,
  tipo,
  categoria,
  dre_grupo,
  contraparte_nome,
  fornecedor,
  espera_zerar,
  status_conciliacao,
  qtd_candidatos,
  par_origem,
  par_data,
  par_valor,
  par_categoria,
  par_contraparte,
  dias_diferenca,
  atualizado_em
from public.mv_conciliacao_contabil
where public.usuario_pode_acessar_pagina('conciliacao_contabil.html');

create or replace view public.app_conciliacao_contabil_resumo_mensal
with (security_barrier = true, security_invoker = false) as
select
  ano_mes,
  status_conciliacao,
  count(*)::integer as qtd,
  round(sum(valor), 2) as total,
  round(coalesce(sum(valor) filter (where valor > 0), 0), 2) as creditos,
  round(coalesce(sum(valor) filter (where valor < 0), 0), 2) as debitos,
  max(atualizado_em) as atualizado_em
from public.mv_conciliacao_contabil
where public.usuario_pode_acessar_pagina('conciliacao_contabil.html')
group by ano_mes, status_conciliacao;

comment on view public.app_conciliacao_contabil is
  'Detalhe protegido da conciliacao contabil para a rotina conciliacao_contabil.html.';
comment on view public.app_conciliacao_contabil_resumo_mensal is
  'Resumo mensal protegido da conciliacao contabil por status.';

revoke all on public.app_conciliacao_contabil from public, anon;
revoke all on public.app_conciliacao_contabil_resumo_mensal from public, anon;
grant select on public.app_conciliacao_contabil to authenticated;
grant select on public.app_conciliacao_contabil_resumo_mensal to authenticated;

insert into public.pagina_permissao (pagina, papeis)
values ('conciliacao_contabil.html', array['socio'])
on conflict (pagina) do nothing;

create or replace function public.refresh_painel()
returns void
language plpgsql
security definer
set search_path = public
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

commit;
