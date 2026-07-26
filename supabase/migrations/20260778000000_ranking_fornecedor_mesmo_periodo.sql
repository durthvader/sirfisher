-- =====================================================================
-- Ranking de fornecedores compara o mesmo periodo, nao a tendencia
-- =====================================================================
--
-- PROBLEMA
--   O ranking de `despesas.html` comparava o mes corrente com a media
--   historica aplicando a **tendencia**, que e um multiplicador derivado
--   da curva de VENDAS. Isso quebra para todo gasto que nao acompanha
--   venda:
--
--     - despesa fixa e paga uma vez e acabou (imposto, energia, aluguel,
--       folha, plano de beneficio). Projetar essa despesa pelo avanco do
--       mes inventa gasto que nao vai existir;
--     - insumo varia ao longo do mes, e ai a projecao ate faz sentido.
--
--   Medido em jul/2026 (corte no dia 25), comparando a media dos meses
--   anteriores no mes cheio x no mesmo ponto do mes:
--
--     fornecedor          media ate dia 26   media mes cheio
--     Imposto                    8.579,09          8.579,09   <- identicas
--     IFOOD BENEFICIOS           5.692,51          5.692,51   <- identicas
--     Enel                       3.016,56          3.016,56   <- identicas
--     B&C                        6.525,87          7.284,14   <- 90%
--     Ambev                      7.971,32          9.730,28   <- 82%
--     SOLMAR                     7.050,21          8.190,43   <- 86%
--
--   Onde as duas medias sao identicas, historicamente nada e pago depois
--   do dia 26 -- e a tendencia so inflava. Onde diferem, a compra
--   realmente continua ate o fim do mes.
--
--   **O proprio dado separa fixo de variavel.** Cortando os dois lados no
--   mesmo dia do mes, nao e preciso marcar quem e quem.
--
-- SOLUCAO
--   + `mv_despesa_diaria`: mesma agregacao da `mv_despesa_mensal`, so que
--     por **dia** em vez de mes. 13.425 linhas, 1,1 MB.
--   + `listar_ranking_fornecedor(p_ano_mes, p_meses_base)`: devolve os
--     fornecedores do mes com o realizado ate o dia de corte e a media dos
--     meses anteriores **ate o mesmo dia**. Sem tendencia, sem projecao:
--     os dois lados cobrem a mesma fatia do mes.
--   ~ `refresh_painel()` passa a atualizar a MV nova junto com as outras.
--
--   Em mes fechado nao ha corte (o dia vai a 31 e cobre o mes inteiro),
--   entao o comportamento historico nao muda.
--
-- POR QUE UMA MV, E NAO LER O fato_financeiro DIRETO
--   A primeira versao lia o `fato_financeiro` e levava **1,5 s** (medido:
--   1.588 ms na funcao, 1.541 ms de tempo de servidor no explain, contra
--   49 ms de latencia de rede -- e custo de servidor, nao de rede).
--   O motivo: `data_competencia` e coluna **calculada** por ramo da view,
--   entao filtrar por periodo nao usa indice e obriga a materializar a
--   uniao das cinco raws mais o de_para. Marcar a CTE como MATERIALIZED
--   nao ajudou, o que confirma que o custo e a montagem da view, nao
--   expansao repetida.
--
--   Com a MV diaria o filtro por periodo vira index scan: **183 ms**,
--   mesmos 63 fornecedores e mesmos valores. Fica no mesmo padrao ja
--   usado por `mv_despesa_mensal`, com o mesmo ciclo de refresh.
--
-- FOLHA E DIARIAS COLAPSADAS
--   As categorias `Folha Salarial` e `Diária` viram **uma linha cada**,
--   com a contagem de pessoas em `pessoas`. Sao ~58 pessoas fisicas
--   disputando 15 posicoes com fornecedor negociavel, e o salario
--   individual nao e a informacao util -- a folha no todo e. Colapsar (em
--   vez de remover) mantem visivel o maior bloco de gasto da casa: em
--   jul/2026 a folha aparece em 1o lugar com R$ 53.046,22 e 33 pessoas.
--   De quebra, tira o salario individual da tela.
--
--   As demais categorias de PESSOAL seguem individuais de proposito:
--   iFood Beneficios, Plano Dentario, Fardamento e Endomarketing sao
--   fornecedores de verdade, negociaveis como qualquer outro.
--
-- LIMITACOES ASSUMIDAS
--   - Boleto que muda de dia entre meses (pago dia 10 num mes, dia 28 no
--     outro) gera variacao falsa enquanto o mes nao fecha. Se corrige
--     sozinho no fechamento.
--   - Comparar por dia do mes trata fevereiro de forma levemente
--     assimetrica (corte no dia 30 pega fevereiro inteiro). Efeito
--     desprezivel e so em mes corrente.
--   - A MV so reflete importacao depois do `refresh_painel()`, igual as
--     demais MVs do painel.
--
-- OBJETOS
--   + public.mv_despesa_diaria (+ indice unico e indice por dia)
--   + public.listar_ranking_fornecedor(text, integer)
--   ~ public.refresh_painel()
--
-- RISCO: baixo. Objetos novos e uma funcao de refresh que ganha uma
--   linha. Nada existente muda de forma ou de resultado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- MV diaria: mesma regra da mv_despesa_mensal, granularidade de dia
-- ---------------------------------------------------------------------
create materialized view if not exists public.mv_despesa_diaria as
select
  ff.data_competencia as dia,
  case
    when ff.dre_grupo is null or ff.dre_grupo = '#N/A' then 'Não classificado'
    else ff.dre_grupo
  end as grupo,
  coalesce(nullif(ff.categoria, ''), '(sem categoria)') as categoria,
  coalesce(nullif(ff.fornecedor, ''), nullif(ff.contraparte_nome, ''), '(sem nome)') as fornecedor,
  round(sum(abs(ff.valor)), 2) as valor,
  count(*)::integer as lancamentos
from public.fato_financeiro ff
where ff.natureza = 'Despesa'
  and ff.entra_dre
  and ff.unidade = 'PRAIA'
  and coalesce(ff.dre_grupo, '') <> 'CONTABIL'
  and ff.data_competencia is not null
group by 1, 2, 3, 4;

-- Unico obrigatorio para o refresh concurrently.
create unique index if not exists mv_despesa_diaria_key_idx
  on public.mv_despesa_diaria (dia, grupo, categoria, fornecedor);

create index if not exists mv_despesa_diaria_dia_idx
  on public.mv_despesa_diaria (dia);

comment on materialized view public.mv_despesa_diaria is
  'Despesa da PRAIA por dia/grupo/categoria/fornecedor. Igual a mv_despesa_mensal, so que diaria -- existe para o ranking poder cortar no mesmo dia do mes sem pagar o custo de filtrar o fato_financeiro por data_competencia (coluna calculada, sem indice).';

-- Nao exposta na Data API de proposito: o acesso e pela RPC abaixo.
revoke all on public.mv_despesa_diaria from anon, authenticated;

-- ---------------------------------------------------------------------
-- Refresh: a MV nova entra no mesmo ciclo das demais
-- ---------------------------------------------------------------------
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
end;
$function$;

-- ---------------------------------------------------------------------
-- Ranking: realizado ate o corte x media dos meses anteriores ate o
-- mesmo dia do mes
-- ---------------------------------------------------------------------
create or replace function public.listar_ranking_fornecedor(
  p_ano_mes text,
  p_meses_base integer default 6
)
returns table (
  fornecedor text,
  grupo text,
  valor numeric,
  lancamentos integer,
  media numeric,
  meses_base integer,
  pessoas integer,
  dia_corte integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_mes   date;
  v_corte date;
  v_dia   integer;
begin
  if not public.usuario_tem_papel(array['admin', 'socio']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_ano_mes is null or p_ano_mes !~ '^\d{4}-\d{2}$' then
    raise exception using errcode = '22023', message = 'Periodo invalido.';
  end if;

  p_meses_base := least(greatest(coalesce(p_meses_base, 6), 1), 24);
  v_mes := to_date(p_ano_mes || '-01', 'YYYY-MM-DD');

  select c.dia into v_corte from public.corte_caixa c;

  -- No mes em andamento o corte limita os DOIS lados da comparacao.
  -- Em mes fechado o dia 31 cobre o mes inteiro, entao nao ha corte.
  v_dia := case
             when v_corte is not null
              and date_trunc('month', v_corte)::date = v_mes
               then extract(day from v_corte)::integer
             else 31
           end;

  return query
  with base as (
    select
      date_trunc('month', d.dia)::date as mes,
      -- Folha e diaria colapsam num rotulo unico; o resto mantem o
      -- fornecedor individual.
      case
        when d.categoria = 'Folha Salarial' then 'Folha salarial'
        when d.categoria = 'Diária'         then 'Diárias'
        else d.fornecedor
      end as forn,
      (d.categoria in ('Folha Salarial', 'Diária')) as coletivo,
      d.fornecedor as pessoa,
      d.grupo as grp,
      d.valor,
      d.lancamentos
    from public.mv_despesa_diaria d
    where d.dia >= (v_mes - make_interval(months => p_meses_base))::date
      and d.dia <  (v_mes + interval '1 month')::date
      and extract(day from d.dia)::integer <= v_dia
  ), dominante as (
    -- Grupo que mais pesa no mes corrente, para a cor e o chip da barra.
    select distinct on (b.forn) b.forn, b.grp
    from base b
    where b.mes = v_mes
    group by b.forn, b.grp
    order by b.forn, sum(b.valor) desc
  )
  select
    b.forn,
    d.grp,
    round(coalesce(sum(b.valor) filter (where b.mes = v_mes), 0), 2),
    coalesce(sum(b.lancamentos) filter (where b.mes = v_mes), 0)::integer,
    round(sum(b.valor) filter (where b.mes < v_mes)
          / nullif(count(distinct b.mes) filter (where b.mes < v_mes), 0), 2),
    count(distinct b.mes) filter (where b.mes < v_mes)::integer,
    case when bool_or(b.coletivo)
         then count(distinct b.pessoa) filter (where b.mes = v_mes)::integer
    end,
    v_dia
  from base b
  join dominante d on d.forn = b.forn
  group by b.forn, d.grp
  having coalesce(sum(b.valor) filter (where b.mes = v_mes), 0) > 0
  order by 3 desc;
end;
$function$;

comment on function public.listar_ranking_fornecedor(text, integer) is
  'Fornecedores do mes com o realizado ate o dia de corte e a media dos meses anteriores ate o MESMO dia do mes. Sem tendencia. Folha Salarial e Diária vem colapsadas numa linha cada, com a contagem em pessoas.';

revoke all on function public.listar_ranking_fornecedor(text, integer) from public;
grant execute on function public.listar_ranking_fornecedor(text, integer) to authenticated;
