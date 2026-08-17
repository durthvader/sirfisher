-- =====================================================================
-- A cascata da DRE passa a fechar: grupo residual ganha barra
-- =====================================================================
--
-- PROBLEMA
--   Na "Cascata do resultado realizado" do Painel do Gerente, a barra de
--   Resultado líquido não alinhava com o fim da última barra. Em
--   agosto/2026 os passos exibidos terminavam em -14,0% da receita, mas o
--   Resultado líquido aparecia em -16,1%. Faltavam 2,1 pontos.
--
--   Causa: `painel_dre_cascata` ENUMERA os grupos que viram barra
--   (RECEITAS, DESPESA DIRETA DE VENDA, IMPOSTOS, PESSOAL, INFRAESTRUTURA,
--   MARKETING E PUBLICIDADE, NÃO OPERACIONAL, CONTABIL, BENS DURÁVEIS e os
--   sem classificação), mas `resultado_liquido` é `total_geral` -- a soma de
--   TODOS os grupos. Qualquer grupo fora da lista entra no total e não ganha
--   barra nenhuma: soma sem parcela.
--
--   O grupo que caiu no buraco é `CARTÃO DE CRÉDITO` (categoria "Cartão
--   BTG"): pagamentos de fatura vindos do extrato Stone. Não é anomalia de
--   agosto -- medido mês a mês, o furo vai de -1,0% a -2,3% da receita:
--
--     2026-08  -2.398,22 (-2,1%)     2026-04  -3.392,09 (-1,8%)
--     2026-07  -1.963,09 (-1,0%)     2026-03  -2.752,09 (-2,1%)
--     2026-06  -1.719,11 (-1,0%)     2026-02  -3.376,90 (-2,3%)
--     2026-05  -1.901,68 (-1,4%)     2026-01  -3.021,06 (-1,7%)
--
--   O mesmo furo existia em três lugares, porque cada tela reenumera os
--   grupos: a cascata do gerente, a cascata da DRE e a tabela da DRE. E
--   `resultado_liquido_projetado_perc` somava
--   `operacional + nao_operacional + contabil + capex + nao_categorizado`,
--   também sem o residual -- ou seja, o líquido PROJETADO estava otimista
--   pelo mesmo valor.
--
-- SOLUÇÃO
--   `painel_dre_cascata` ganha a coluna `outros`, definida por subtração:
--   o que sobra do `total_geral` depois de todos os grupos enumerados.
--   Assim a identidade passa a valer por construção -- grupo novo no plano
--   de contas aparece automaticamente em `outros` em vez de evaporar.
--
--   A definição do residual fica num único lugar; as views `app_*` só
--   expõem a coluna, e o front-end ganha um passo "Outros" na cascata.
--
--   A validação ABORTA se a identidade não fechar em qualquer mês, então
--   este defeito não pode voltar em silêncio.
--
-- OBJETOS
--   ~ public.painel_dre_cascata           (+ coluna outros, no fim)
--   ~ public.app_painel_dre_cascata       (+ coluna outros, no fim)
--   ~ public.app_gerente_dre_cascata_perc (+ outros_perc; corrige o líquido
--                                          projetado, que omitia o residual)
--
-- IMPACTO
--   Nenhum valor de DRE muda. `resultado_liquido` já continha o grupo; ele
--   só passa a ser exibido. O único número que muda é
--   `resultado_liquido_projetado_perc`, que estava otimista por omissão.
--
-- CLASSIFICAÇÃO DO "CARTÃO BTG": fica como está, de propósito.
--   Hoje o pagamento da fatura entra como despesa e o total está correto no
--   resultado; o que falta é a decomposição por natureza (o gasto não
--   aparece em CMV, Pessoal, etc.). Importar as faturas itemizadas é
--   projeto separado e exige, no mesmo movimento, transformar o pagamento
--   da fatura em transferência -- senão o gasto conta duas vezes.
--
-- RISCO: baixo. Só acrescenta coluna derivada por subtração e uma barra na
--   tela. Nenhuma tabela, grant, gate ou coluna existente é alterada.
-- =====================================================================

begin;

-- Guarda o retrato de antes para provar que nada existente mudou.
create temporary table cascata_antes on commit drop as
select mes, ano_mes, receita, cmv, impostos, margem_contribuicao, mc_perc,
       pessoal, infraestrutura, marketing, resultado_operacional, margem_op_perc,
       nao_operacional, contabil, capex, nao_categorizado, resultado_liquido,
       margem_liq_perc, cmv_perc, pessoal_perc
from public.painel_dre_cascata;

-- 1) O residual, definido num único lugar.
create or replace view public.painel_dre_cascata as
with base as (
  select dre_mensal.mes,
    dre_mensal.ano_mes,
    dre_mensal.dre_grupo,
    dre_mensal.natureza,
    sum(dre_mensal.total) as total
  from dre_mensal
  where dre_mensal.entra_dre = true and dre_mensal.unidade = 'PRAIA'::text
  group by dre_mensal.mes, dre_mensal.ano_mes, dre_mensal.dre_grupo, dre_mensal.natureza
), flags as (
  select grupo_variavel.grupo, grupo_variavel.variavel from grupo_variavel
), agg as (
  select b.mes,
    b.ano_mes,
    sum(b.total) as total_geral,
    sum(case when b.dre_grupo = 'RECEITAS'::text then b.total else 0::numeric end) as receita,
    sum(case when f.variavel then b.total else 0::numeric end) as variaveis,
    sum(case when b.dre_grupo = 'DESPESA DIRETA DE VENDA'::text then b.total else 0::numeric end) as cmv,
    sum(case when b.dre_grupo = 'IMPOSTOS'::text then b.total else 0::numeric end) as impostos,
    sum(case when b.dre_grupo = 'PESSOAL'::text then b.total else 0::numeric end) as pessoal,
    sum(case when b.dre_grupo = 'INFRAESTRUTURA'::text then b.total else 0::numeric end) as infraestrutura,
    sum(case when b.dre_grupo = 'MARKETING E PUBLICIDADE'::text then b.total else 0::numeric end) as marketing,
    sum(case when b.dre_grupo = 'NÃO OPERACIONAL'::text then b.total else 0::numeric end) as nao_operacional,
    sum(case when b.dre_grupo = 'CONTABIL'::text then b.total else 0::numeric end) as contabil,
    sum(case when b.dre_grupo = 'BENS DURÁVEIS'::text then b.total else 0::numeric end) as capex,
    sum(case when b.dre_grupo is null or b.dre_grupo = '#N/A'::text then b.total else 0::numeric end) as nao_categorizado
  from base b
    left join flags f on f.grupo = b.dre_grupo
  group by b.mes, b.ano_mes
)
select mes,
  ano_mes,
  round(receita, 2) as receita,
  round(cmv, 2) as cmv,
  round(impostos, 2) as impostos,
  round(receita + variaveis, 2) as margem_contribuicao,
  case when receita > 0::numeric then round((receita + variaveis) / receita * 100::numeric, 1) else null::numeric end as mc_perc,
  round(pessoal, 2) as pessoal,
  round(infraestrutura, 2) as infraestrutura,
  round(marketing, 2) as marketing,
  round(receita + variaveis + pessoal + infraestrutura + marketing, 2) as resultado_operacional,
  case when receita > 0::numeric then round((receita + variaveis + pessoal + infraestrutura + marketing) / receita * 100::numeric, 1) else null::numeric end as margem_op_perc,
  round(nao_operacional, 2) as nao_operacional,
  round(contabil, 2) as contabil,
  round(capex, 2) as capex,
  round(nao_categorizado, 2) as nao_categorizado,
  round(total_geral, 2) as resultado_liquido,
  case when receita > 0::numeric then round(total_geral / receita * 100::numeric, 1) else null::numeric end as margem_liq_perc,
  case when receita > 0::numeric then round((- cmv) / receita * 100::numeric, 1) else null::numeric end as cmv_perc,
  case when receita > 0::numeric then round((- pessoal) / receita * 100::numeric, 1) else null::numeric end as pessoal_perc,
  -- Tudo que o total contém e nenhuma barra mostra. Por subtração, para que
  -- grupo novo no plano de contas apareça aqui em vez de desaparecer.
  round(total_geral
        - (receita + variaveis + pessoal + infraestrutura + marketing
           + nao_operacional + contabil + capex + nao_categorizado), 2) as outros
from agg
order by mes;

comment on view public.painel_dre_cascata is
  'Cascata da DRE por mês. A coluna outros é o residual por subtração entre resultado_liquido (total de todos os grupos) e os grupos enumerados, para que nenhum grupo fique fora da cascata em silêncio.';

-- 2) As views app_* só expõem a coluna nova, no fim.
create or replace view public.app_painel_dre_cascata
with (security_barrier = true, security_invoker = false) as
select mes, ano_mes, receita, cmv, impostos, margem_contribuicao, mc_perc,
  pessoal, infraestrutura, marketing, resultado_operacional, margem_op_perc,
  nao_operacional, contabil, capex, nao_categorizado, resultado_liquido,
  margem_liq_perc, cmv_perc, pessoal_perc, outros
from painel_dre_cascata s
where usuario_pode_acessar_alguma_pagina(array['index.html'::text, 'dre.html'::text]);

grant select on public.app_painel_dre_cascata to authenticated;

-- 3) A view do gerente é grande e recalcula projeção; alterar por cirurgia
--    de texto, exigindo correspondência única, é menos arriscado que
--    reescrever à mão.
do $cirurgia$
declare
  v_def text := pg_get_viewdef('public.app_gerente_dre_cascata_perc'::regclass, true);
  v_novo text;
  v_ancora text;
begin
  -- 3a) O residual precisa atravessar as três CTEs que enumeram colunas.
  if (length(v_def) - length(replace(v_def, 's_1.pessoal_perc,', ''))) / length('s_1.pessoal_perc,') <> 1
     or (length(v_def) - length(replace(v_def, 'b.pessoal_perc,', ''))) / length('b.pessoal_perc,') <> 1
     or (length(v_def) - length(replace(v_def, 'p.pessoal_perc,', ''))) / length('p.pessoal_perc,') <> 1 then
    raise exception 'As CTEs da view do gerente não têm a forma esperada; abortando cirurgia.';
  end if;

  v_novo := replace(v_def, 's_1.pessoal_perc,', 's_1.pessoal_perc, s_1.outros,');
  v_novo := replace(v_novo, 'b.pessoal_perc,', 'b.pessoal_perc, b.outros,');
  v_novo := replace(v_novo, 'p.pessoal_perc,', 'p.pessoal_perc, p.outros,');

  -- 3b) O líquido projetado omitia o residual.
  if (length(v_novo) - length(replace(v_novo,
        'resultado_operacional_projetado + nao_operacional + contabil + capex + nao_categorizado', '')))
     / length('resultado_operacional_projetado + nao_operacional + contabil + capex + nao_categorizado') <> 1 then
    raise exception 'O líquido projetado não tem a forma esperada; abortando cirurgia.';
  end if;

  v_novo := replace(v_novo,
    'resultado_operacional_projetado + nao_operacional + contabil + capex + nao_categorizado',
    'resultado_operacional_projetado + nao_operacional + contabil + capex + nao_categorizado + outros');

  -- 3c) A coluna nova entra no FIM, senão create or replace recusa. O nome
  --     `em_projecao` atravessa as CTEs (aparece 6 vezes), então o âncora
  --     tem de ser o trecho que só existe no SELECT final.
  v_ancora := 'em_projecao' || chr(10) || '   FROM resultado s';

  if (length(v_novo) - length(replace(v_novo, v_ancora, ''))) / length(v_ancora) <> 1 then
    raise exception 'O SELECT final da view do gerente não tem a forma esperada; abortando cirurgia.';
  end if;

  v_novo := replace(v_novo, v_ancora,
    'em_projecao,' || chr(10) ||
    '    round(100.0 * outros / NULLIF(receita, 0::numeric), 1) AS outros_perc' || chr(10) ||
    '   FROM resultado s');

  execute 'create or replace view public.app_gerente_dre_cascata_perc '
       || 'with (security_barrier = true, security_invoker = false) as ' || v_novo;
end;
$cirurgia$;

grant select on public.app_gerente_dre_cascata_perc to authenticated;

-- Confere os objetos efetivos, não apenas o texto desta migration.
do $validacao$
declare
  v_dif integer;
  v_aberto record;
  v_gerente text := pg_get_viewdef('public.app_gerente_dre_cascata_perc'::regclass, true);
begin
  -- Nada do que já existia pode ter mudado.
  select count(*) into v_dif
  from cascata_antes a
  join public.painel_dre_cascata d on d.mes = a.mes
  where (a.receita, a.cmv, a.impostos, a.margem_contribuicao, a.mc_perc,
         a.pessoal, a.infraestrutura, a.marketing, a.resultado_operacional,
         a.margem_op_perc, a.nao_operacional, a.contabil, a.capex,
         a.nao_categorizado, a.resultado_liquido, a.margem_liq_perc,
         a.cmv_perc, a.pessoal_perc)
     is distinct from
        (d.receita, d.cmv, d.impostos, d.margem_contribuicao, d.mc_perc,
         d.pessoal, d.infraestrutura, d.marketing, d.resultado_operacional,
         d.margem_op_perc, d.nao_operacional, d.contabil, d.capex,
         d.nao_categorizado, d.resultado_liquido, d.margem_liq_perc,
         d.cmv_perc, d.pessoal_perc);

  if v_dif > 0 then
    raise exception 'A cascata mudou em % meses; esta migration só deveria acrescentar coluna.', v_dif;
  end if;

  if (select count(*) from cascata_antes) <> (select count(*) from public.painel_dre_cascata) then
    raise exception 'O número de meses da cascata mudou.';
  end if;

  -- A identidade tem de fechar em TODO mês: é o defeito que originou isto.
  for v_aberto in
    select d.ano_mes,
           round(d.resultado_liquido
                 - (d.resultado_operacional + d.nao_operacional + d.contabil
                    + d.capex + d.nao_categorizado + d.outros), 2) as sobra
    from public.painel_dre_cascata d
    where abs(d.resultado_liquido
              - (d.resultado_operacional + d.nao_operacional + d.contabil
                 + d.capex + d.nao_categorizado + d.outros)) > 0.01
  loop
    raise exception 'A cascata de % não fecha: sobram R$ %.', v_aberto.ano_mes, v_aberto.sobra;
  end loop;

  if position('outros_perc' in v_gerente) = 0 then
    raise exception 'A view do gerente não expõe outros_perc.';
  end if;

  if position('capex + nao_categorizado + outros' in v_gerente) = 0 then
    raise exception 'O líquido projetado do gerente continua sem o residual.';
  end if;

  raise notice 'Cascata fecha em todos os meses. Residual de agosto/2026: R$ %.',
    (select outros from public.painel_dre_cascata where ano_mes = '2026-08');
end;
$validacao$;

commit;
