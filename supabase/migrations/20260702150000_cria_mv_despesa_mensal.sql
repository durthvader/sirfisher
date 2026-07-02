-- =====================================================================
-- Snapshot materializado de despesas por mes/grupo/categoria/fornecedor
-- =====================================================================
--
-- OBJETIVO
--   Alimentar a nova pagina Despesas/Fornecedores ("onde o dinheiro vaza")
--   sem estourar o statement_timeout de 3s do role anon. fato_financeiro
--   sozinho leva ~3s; agregar despesas por fornecedor ao vivo em cada
--   abertura de pagina cairia no mesmo problema do caixa.html. Entao
--   materializamos o grao de despesa e a pagina le esse snapshot (rapido),
--   calculando ranking/variacao/anomalia/recorrencia no proprio cliente.
--
-- GRAO
--   uma linha por (mes de competencia, grupo DRE, categoria, fornecedor),
--   com o total (valor absoluto) e a contagem de lancamentos.
--
-- FILTROS (alinhados com a DRE / painel_composicao_despesa)
--   - natureza = 'Despesa' e entra_dre  -> so saidas reais; entra_dre ja
--     remove CARTAO DE CREDITO e TRANSFERENCIA.
--   - exclui CONTABIL (ajuste contabil, nao e vazamento de caixa real).
--   - unidade = 'PRAIA'.
--   - grupo nulo ou '#N/A' vira 'Nao classificado' (dinheiro sem rastreio,
--     que a pagina destaca como alerta).
--
-- OBJETOS
--   + mv_despesa_mensal   (novo materialized view + indice unico)
--   ~ refresh_painel()    (passa a atualizar tambem este snapshot)
--
-- RISCO: baixo.
--   - Objeto novo, nao altera nenhuma view/pagina existente.
--   - refresh_painel() ganha mais um REFRESH CONCURRENTLY (nao bloqueia
--     leituras); rodado ao fim das importacoes, como o mv do caixa.
--   - ~5,7 mil linhas no total (56 meses); a pagina le so a janela dela.
-- =====================================================================

create materialized view if not exists mv_despesa_mensal as
select
  date_trunc('month', ff.data_competencia)::date                              as mes,
  to_char(date_trunc('month', ff.data_competencia), 'YYYY-MM')                 as ano_mes,
  case when ff.dre_grupo is null or ff.dre_grupo = '#N/A'
       then 'Não classificado' else ff.dre_grupo end                          as grupo,
  coalesce(nullif(ff.categoria, ''), '(sem categoria)')                       as categoria,
  coalesce(nullif(ff.fornecedor, ''), nullif(ff.contraparte_nome, ''), '(sem nome)') as fornecedor,
  round(sum(abs(ff.valor)), 2)                                                as valor,
  count(*)::int                                                               as lancamentos
from fato_financeiro ff
where ff.natureza = 'Despesa'
  and ff.entra_dre
  and ff.unidade = 'PRAIA'
  and coalesce(ff.dre_grupo, '') <> 'CONTABIL'
  and ff.data_competencia is not null
group by 1, 2, 3, 4, 5
with data;

-- indice unico (grao e naturalmente unico pelo group by) -> habilita
-- REFRESH ... CONCURRENTLY.
create unique index if not exists mv_despesa_mensal_key_idx
  on mv_despesa_mensal (mes, grupo, categoria, fornecedor);

-- indice de apoio para o filtro por janela de meses que a pagina usa.
create index if not exists mv_despesa_mensal_mes_idx
  on mv_despesa_mensal (mes);

grant select on mv_despesa_mensal to anon, authenticated;

-- refresh_painel() passa a atualizar tambem o snapshot de despesas.
create or replace function refresh_painel()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  set local statement_timeout = 0;
  refresh materialized view concurrently mv_fluxo_caixa_diario;
  refresh materialized view concurrently mv_despesa_mensal;
end;
$$;
