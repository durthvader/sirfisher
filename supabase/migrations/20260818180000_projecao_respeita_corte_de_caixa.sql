-- =====================================================================
-- Projeção de despesa fixa respeita o corte de caixa
-- =====================================================================
--
-- PROBLEMA
--   Em 14/08/2026 o Calendário projetava fechar agosto com R$ 190.062,34
--   depois de um pagamento de contas feito no mesmo dia. O valor estava
--   inflado em R$ 28.398,71 -- exatamente o que saiu do caixa naquele dia.
--
--   O corte de caixa é `least(max(fato_financeiro.data_caixa), hoje - 1)`.
--   O extrato importado já trazia as movimentações do próprio dia, então
--   fato_financeiro tinha lançamentos com data_caixa = 14/08 enquanto o
--   corte permanecia em 13/08. A partir daí:
--
--     - listar_calendario_financeiro trata todo dia > corte como projetado
--       e ignora o realizado desses dias (é o comportamento desejado: o dia
--       corrente ainda está incompleto);
--     - projecao_despesa_fixa calcula quanto falta gastar no mês como
--       `média mensal - realizado do mês`, e esse realizado somava TODO o
--       fato_financeiro da competência, inclusive os lançamentos com
--       data_caixa posterior ao corte.
--
--   Resultado: o mesmo dinheiro saía da projeção (porque já constava como
--   realizado por competência) sem entrar no realizado do caixa (porque o
--   dia está além do corte). Conferido no banco: realizado de agosto por
--   competência R$ 88.513,08, dos quais R$ 28.398,71 com data_caixa fora do
--   corte. A projeção fixa de 14--31/08 tinha caído de R$ 50.881,19 para
--   R$ 21.720,15.
--
--   O efeito colateral conhecido -- marcar contas como pagas na rotina
--   "conta corrente" -- não era a causa: `greatest(média - realizado -
--   contas_abertas, 0) + contas_abertas` é neutro no total do mês enquanto o
--   resíduo é positivo. A marcação só muda a distribuição por dia.
--
-- SOLUÇÃO
--   Duas mudanças nas views de despesa fixa, mantendo colunas e tipos:
--
--   1. `realizado_mes` passa a contar apenas o que já está dentro do corte
--      (`f.data_caixa <= corte`). Despesa lançada com data de caixa
--      posterior ao corte continua na projeção, que é onde o Calendário
--      ainda a exibe.
--
--   2. `contas_abertas` deixa de descartar toda conta que tenha registro de
--      pagamento. Conta marcada como paga cuja data de pagamento ainda é
--      posterior ao corte volta para a projeção, agora com o VALOR REAL
--      pago e no DIA do pagamento, em vez da média no vencimento. Contas em
--      `sem_movimento` e pagamentos já dentro do corte seguem excluídos.
--
--   As duas juntas mantêm a identidade `total projetado do mês = média -
--   realizado dentro do corte`, sem contagem dupla: quando o corte avança
--   para o dia do pagamento, a condição 2 deixa de casar, a condição 1 passa
--   a contar o valor como realizado e o Calendário lê o extrato -- a
--   transição acontece sem degrau.
--
--   Acrescenta ainda `public.resumo_corte_caixa()`, que expõe o que já foi
--   lançado depois do corte. O Calendário usa isso para avisar na tela em
--   vez de deixar a divergência silenciosa, que foi o que permitiu o erro
--   passar despercebido.
--
-- OBJETOS
--   ~ public.projecao_despesa_fixa       (view, mesmas colunas)
--   ~ public.painel_colchao_despesa_fixa (view, mesmas colunas)
--   + public.resumo_corte_caixa()        (função nova, leitura)
--
-- IMPACTO MEDIDO (leitura antes da migration, corte em 13/08/2026)
--   agosto/2026:  R$ 21.720,15 -> R$ 50.118,88  (+28.398,73)
--   setembro/2026 e outubro/2026: inalterados
--   fechamento projetado de agosto: R$ 190.062,34 -> ~R$ 161.663,61
--
-- RISCO: baixo.
--   - Nenhuma tabela é alterada; só views e uma função de leitura.
--   - Meses futuros não mudam (não têm realizado nem pagamento lançado).
--   - Meses fechados não mudam (todo o realizado já está dentro do corte).
--   - Sem alteração de assinatura, colunas, tipos, grants ou policies.
-- =====================================================================

begin;

-- 1) Projeção diária de despesa fixa.
create or replace view public.projecao_despesa_fixa as
with cfg as (
  select greatest(1, public.parametro_valor('meses_media_fixa', 3)::integer) as meses
), corte as (
  select dia from public.corte_caixa
), media as (
  select coalesce(avg(m.total), 0::numeric) as media_mensal
  from (
    select date_trunc('month', f.data_competencia) as mes, sum(abs(f.valor)) as total
    from public.fato_financeiro f cross join cfg
    where f.movimentacao like 'D%'
      and f.dre_grupo = any (array['PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'])
      and f.data_competencia >= date_trunc('month', current_date) - make_interval(months => cfg.meses)
      and f.data_competencia < date_trunc('month', current_date)
    group by 1
  ) m
), realizado_mes as (
  -- Só entra como realizado o que o Calendário já mostra como realizado, ou
  -- seja, o que tem data de caixa dentro do corte. Lançamento com data de
  -- caixa posterior continua sendo projeção.
  select date_trunc('month', f.data_competencia) as mes, sum(abs(f.valor)) as realizado
  from public.fato_financeiro f cross join corte ct
  where f.movimentacao like 'D%'
    and f.dre_grupo = any (array['PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'])
    and f.data_caixa <= ct.dia
  group by 1
), dias_restantes as (
  select c.mes, count(*) as n
  from public.calendario c cross join corte ct
  where c.dia > ct.dia group by c.mes
), contas_abertas as (
  select dr.mes,
    case when cp.id is not null
              and cp.data_pagamento >= dr.mes
              and cp.data_pagamento < (dr.mes + interval '1 month')::date
           then cp.data_pagamento
         when v.vencimento > ct.dia then v.vencimento
         else (select min(c.dia) from public.calendario c where c.mes = dr.mes and c.dia > ct.dia)
    end as dia,
    case when cp.id is not null then cp.valor else m.media_periodo end as valor
  from dias_restantes dr
  cross join corte ct
  cross join cfg
  join public.conta_recorrente cr on cr.ativa and cr.tipo = 'despesa' and cr.incluir_totais
  cross join lateral (
    select least((dr.mes + (cr.dia_vencimento - 1) * interval '1 day')::date,
                 (dr.mes + interval '1 month - 1 day')::date) as vencimento
  ) v
  -- Pagamento já registrado mas com data posterior ao corte: o caixa ainda
  -- não o absorveu, então ele permanece projetado pelo valor real e no dia
  -- em que foi pago.
  left join public.conta_recorrente_pagamento cp
    on cp.conta_id = cr.id and cp.competencia = dr.mes
   and cp.situacao = 'pago' and cp.data_pagamento > ct.dia and cp.valor > 0
  cross join lateral (
    select round(avg(h.valor), 2) as media_periodo
    from (
      select p.valor from public.conta_recorrente_pagamento p
      where p.conta_id = cr.id and p.competencia < dr.mes
        and p.situacao = 'pago' and p.valor > 0
      order by p.competencia desc limit (select meses from cfg)
    ) h
  ) m
  where (
      cp.id is not null
      or not exists (
        select 1 from public.conta_recorrente_pagamento cx
        where cx.conta_id = cr.id and cx.competencia = dr.mes
      )
    )
    and (case when cp.id is not null then cp.valor else m.media_periodo end) > 0
), contas_abertas_mes as (
  select mes, sum(valor) as total from contas_abertas group by mes
), contas_abertas_dia as (
  select dia, sum(valor) as total from contas_abertas where dia is not null group by dia
)
select c.dia,
  round(greatest((select media_mensal from media) - coalesce(rm.realizado, 0)
                 - coalesce(cam.total, 0), 0) / dr.n::numeric
        + coalesce(cad.total, 0), 2) as valor
from public.calendario c
join dias_restantes dr on dr.mes = c.mes
left join realizado_mes rm on rm.mes = c.mes
left join contas_abertas_mes cam on cam.mes = c.mes
left join contas_abertas_dia cad on cad.dia = c.dia
cross join corte ct
where c.dia > ct.dia;

-- 2) Painel que explica a mesma conta. Precisa da mesma regra, senão passa a
--    contradizer a projeção que ele descreve.
create or replace view public.painel_colchao_despesa_fixa as
with cfg as (
  select greatest(1, public.parametro_valor('meses_media_fixa', 3)::integer) as meses
), corte as (
  select dia from public.corte_caixa
), media as (
  select coalesce(avg(m.total), 0::numeric) as media_mensal
  from (
    select date_trunc('month', f.data_competencia) as mes, sum(abs(f.valor)) as total
    from public.fato_financeiro f cross join cfg
    where f.movimentacao like 'D%'
      and f.dre_grupo = any (array['PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'])
      and f.data_competencia >= date_trunc('month', current_date) - make_interval(months => cfg.meses)
      and f.data_competencia < date_trunc('month', current_date)
    group by 1
  ) m
), realizado_mes as (
  select date_trunc('month', f.data_competencia) as mes, sum(abs(f.valor)) as realizado
  from public.fato_financeiro f cross join corte ct
  where f.movimentacao like 'D%'
    and f.dre_grupo = any (array['PESSOAL', 'INFRAESTRUTURA', 'MARKETING E PUBLICIDADE', 'IMPOSTOS'])
    and f.data_caixa <= ct.dia
  group by 1
), dias_restantes as (
  select c.mes, count(*) as n from public.calendario c cross join corte ct
  where c.dia > ct.dia group by c.mes
), contas_abertas as (
  select dr.mes,
    case when cp.id is not null then cp.valor else m.media_periodo end as valor
  from dias_restantes dr
  cross join corte ct
  cross join cfg
  join public.conta_recorrente cr on cr.ativa and cr.tipo = 'despesa' and cr.incluir_totais
  left join public.conta_recorrente_pagamento cp
    on cp.conta_id = cr.id and cp.competencia = dr.mes
   and cp.situacao = 'pago' and cp.data_pagamento > ct.dia and cp.valor > 0
  cross join lateral (
    select round(avg(h.valor), 2) as media_periodo
    from (
      select p.valor from public.conta_recorrente_pagamento p
      where p.conta_id = cr.id and p.competencia < dr.mes
        and p.situacao = 'pago' and p.valor > 0
      order by p.competencia desc limit (select meses from cfg)
    ) h
  ) m
  where (
      cp.id is not null
      or not exists (
        select 1 from public.conta_recorrente_pagamento cx
        where cx.conta_id = cr.id and cx.competencia = dr.mes
      )
    )
    and (case when cp.id is not null then cp.valor else m.media_periodo end) > 0
), contas_abertas_mes as (
  select mes, sum(valor) as total from contas_abertas group by mes
)
select dr.mes,
  round((select media_mensal from media), 2) as media_tipica,
  round(coalesce(rm.realizado, 0), 2) as ja_realizado,
  round(greatest((select media_mensal from media) - coalesce(rm.realizado, 0)
                 - coalesce(cam.total, 0), 0), 2) as colchao,
  dr.n as dias_restantes,
  round(greatest((select media_mensal from media) - coalesce(rm.realizado, 0)
                 - coalesce(cam.total, 0), 0) / dr.n::numeric, 2) as valor_dia,
  round(coalesce(cam.total, 0), 2) as contas_abertas
from dias_restantes dr
left join realizado_mes rm on rm.mes = dr.mes
left join contas_abertas_mes cam on cam.mes = dr.mes
order by dr.mes;

-- 3) Torna visível o que já foi lançado além do corte. Reaproveita
--    caixa_real_diario para não duplicar a regra de fontes que entram no
--    caixa.
create or replace function public.resumo_corte_caixa()
returns table (
  corte_caixa date,
  snapshot_saldo date,
  dias_apos_corte integer,
  resultado_apos_corte numeric
)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  return query
  select ct.dia,
         (select max(s.dia) from public.mv_saldo_caixa_diario_detalhado s),
         coalesce((
           select count(*) from public.caixa_real_diario c where c.dia > ct.dia
         ), 0)::integer,
         coalesce((
           select round(sum(c.resultado_real), 2)
           from public.caixa_real_diario c where c.dia > ct.dia
         ), 0::numeric)
  from public.corte_caixa ct;
end;
$function$;

revoke all privileges on function public.resumo_corte_caixa() from public, anon;
grant execute on function public.resumo_corte_caixa() to authenticated;

-- Confere o objeto efetivo, não apenas o texto desta migration.
do $validacao$
declare
  v_fixa text := pg_get_viewdef('public.projecao_despesa_fixa'::regclass, true);
  v_colchao text := pg_get_viewdef('public.painel_colchao_despesa_fixa'::regclass, true);
  v_corte date;
begin
  if position('data_caixa <=' in v_fixa) = 0
     or position('data_caixa <=' in v_colchao) = 0 then
    raise exception 'O realizado das despesas fixas não ficou preso ao corte de caixa.';
  end if;

  if position('cp.data_pagamento >' in v_fixa) = 0
     or position('cp.data_pagamento >' in v_colchao) = 0 then
    raise exception 'As projeções fixas não reconhecem pagamento posterior ao corte.';
  end if;

  select ct.dia into v_corte from public.corte_caixa ct;

  if v_corte is not null and exists (
    select 1 from public.projecao_despesa_fixa p where p.dia <= v_corte
  ) then
    raise exception 'A projeção de despesa fixa invadiu dias já fechados pelo corte.';
  end if;

  if exists (
    select 1 from public.projecao_despesa_fixa p
    where p.valor is null or p.valor < 0
  ) then
    raise exception 'A projeção de despesa fixa produziu valor nulo ou negativo.';
  end if;
end;
$validacao$;

comment on view public.projecao_despesa_fixa is
  'Despesa fixa projetada por dia: média do período menos o realizado dentro do corte de caixa, mais as contas ainda não absorvidas pelo caixa (inclusive as já pagas com data posterior ao corte, pelo valor real).';

comment on view public.painel_colchao_despesa_fixa is
  'Memória de cálculo mensal da projeção de despesa fixa; usa a mesma regra de corte de caixa da projeção diária.';

comment on function public.resumo_corte_caixa() is
  'Posição do corte de caixa, do snapshot diário de saldo e do que já foi lançado depois do corte; alimenta o aviso do Calendário.';

commit;
