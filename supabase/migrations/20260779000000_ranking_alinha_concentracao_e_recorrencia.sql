-- =====================================================================
-- Concentracao e recorrencia passam a usar a mesma base do ranking
-- =====================================================================
--
-- PROBLEMA
--   A 20260778000000 corrigiu o ranking e os vazamentos, mas deixou dois
--   blocos de `despesas.html` na fonte antiga (`mv_despesa_mensal`, sem
--   colapsar folha e sem corte):
--
--     - KPI "Concentracao top 5": contava as ~41 pessoas da folha como 41
--       fornecedores distintos. Isso **subestima** a concentracao, porque
--       o maior bloco de gasto da casa entrava picotado e nunca aparecia
--       no top 5. Alem disso "N fornecedores no mes" contava pessoa
--       fisica como fornecedor.
--     - "Recorrente vs pontual": mesma coisa -- cada pessoa era avaliada
--       individualmente quanto a presenca mensal.
--
--   Resultado visivel: a folha aparecia em 1o lugar no ranking (R$ 53 mil)
--   e simplesmente nao existia como linha nesses dois blocos.
--
-- SOLUCAO
--   A RPC ganha duas colunas e passa a servir os quatro blocos:
--
--     ~ `meses_presente`: em quantos meses anteriores o fornecedor teve
--       gasto, **sem** aplicar o corte de dia. E o dado da recorrencia,
--       que pergunta "aparece todo mes?" -- uma questao estrutural, nao de
--       ritmo. Aplicar o corte aqui classificaria como "pontual" um
--       fornecedor que sempre cobra no fim do mes.
--     ~ `meses_janela`: quantos meses anteriores da janela tem algum
--       gasto. E o denominador do limiar de presenca, que se adapta
--       quando o historico e curto.
--
--   `meses_base` (ja existente) continua sendo a contagem **com** corte,
--   porque e o divisor da media -- ali o corte tem que valer.
--
--   O corte saiu do `where` e virou `filter` nas agregacoes: a mesma
--   passada serve as duas perguntas, sem ler a MV duas vezes.
--
-- OBJETOS
--   ~ public.listar_ranking_fornecedor(text, integer) -- drop + create,
--     porque o tipo de retorno muda (duas colunas novas)
--
--   Nenhum objeto de banco depende desta funcao; quem chama e o
--   `despesas.html`, atualizado no mesmo commit. Colunas novas no fim da
--   lista nao quebram o front-end antigo enquanto o Pages nao publica.
--
-- RISCO: baixo. Funcao `stable`, so leitura, sobre uma MV de 13 mil
--   linhas. Nenhum valor de DRE ou de caixa e tocado.
-- =====================================================================

drop function if exists public.listar_ranking_fornecedor(text, integer);

create function public.listar_ranking_fornecedor(
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
  dia_corte integer,
  meses_presente integer,
  meses_janela integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_mes    date;
  v_corte  date;
  v_dia    integer;
  v_janela integer;
  v_ini    date;
begin
  if not public.usuario_tem_papel(array['admin', 'socio']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_ano_mes is null or p_ano_mes !~ '^\d{4}-\d{2}$' then
    raise exception using errcode = '22023', message = 'Periodo invalido.';
  end if;

  p_meses_base := least(greatest(coalesce(p_meses_base, 6), 1), 24);
  v_mes := to_date(p_ano_mes || '-01', 'YYYY-MM-DD');
  v_ini := (v_mes - make_interval(months => p_meses_base))::date;

  select c.dia into v_corte from public.corte_caixa c;

  -- No mes em andamento o corte limita os DOIS lados da comparacao.
  -- Em mes fechado o dia 31 cobre o mes inteiro, entao nao ha corte.
  v_dia := case
             when v_corte is not null
              and date_trunc('month', v_corte)::date = v_mes
               then extract(day from v_corte)::integer
             else 31
           end;

  -- Quantos meses anteriores da janela realmente tem gasto. O limiar de
  -- presenca se apoia nisso para nao exigir 5 de 6 quando so existem 3.
  select count(distinct date_trunc('month', d.dia)::date)
    into v_janela
  from public.mv_despesa_diaria d
  where d.dia >= v_ini and d.dia < v_mes;

  return query
  with base as (
    select
      date_trunc('month', d.dia)::date as mes,
      extract(day from d.dia)::integer as dia_mes,
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
    where d.dia >= v_ini
      and d.dia <  (v_mes + interval '1 month')::date
  ), dominante as (
    -- Grupo que mais pesa no mes corrente ate o corte, para a cor da barra.
    select distinct on (b.forn) b.forn, b.grp
    from base b
    where b.mes = v_mes and b.dia_mes <= v_dia
    group by b.forn, b.grp
    order by b.forn, sum(b.valor) desc
  )
  select
    b.forn,
    d.grp,
    round(coalesce(sum(b.valor) filter (where b.mes = v_mes and b.dia_mes <= v_dia), 0), 2),
    coalesce(sum(b.lancamentos) filter (where b.mes = v_mes and b.dia_mes <= v_dia), 0)::integer,
    -- Media: os dois lados cortados no mesmo dia do mes.
    round(sum(b.valor) filter (where b.mes < v_mes and b.dia_mes <= v_dia)
          / nullif(count(distinct b.mes) filter (where b.mes < v_mes and b.dia_mes <= v_dia), 0), 2),
    count(distinct b.mes) filter (where b.mes < v_mes and b.dia_mes <= v_dia)::integer,
    case when bool_or(b.coletivo)
         then count(distinct b.pessoa) filter (where b.mes = v_mes and b.dia_mes <= v_dia)::integer
    end,
    v_dia,
    -- Recorrencia: mes cheio, sem corte -- a pergunta e "aparece todo mes?".
    count(distinct b.mes) filter (where b.mes < v_mes)::integer,
    v_janela
  from base b
  join dominante d on d.forn = b.forn
  group by b.forn, d.grp
  having coalesce(sum(b.valor) filter (where b.mes = v_mes and b.dia_mes <= v_dia), 0) > 0
  order by 3 desc;
end;
$function$;

comment on function public.listar_ranking_fornecedor(text, integer) is
  'Fornecedores do mes com realizado ate o dia de corte e media dos meses anteriores ate o MESMO dia. Serve ranking, vazamentos, concentracao e recorrencia de despesas.html. Folha Salarial e Diária vem colapsadas, com a contagem em pessoas. meses_base conta com corte (divisor da media); meses_presente conta o mes cheio (recorrencia).';

revoke all on function public.listar_ranking_fornecedor(text, integer) from public;
grant execute on function public.listar_ranking_fornecedor(text, integer) to authenticated;
