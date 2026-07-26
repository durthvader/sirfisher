-- =====================================================================
-- listar_despesas_dia: mostrar o apelido E o nome do extrato
-- =====================================================================
--
-- PROBLEMA
--   O campo de_para.fornecedor acumula dois usos legitimos: apelido/nome
--   comercial ("Uber" para 25 CPFs de motoristas, "Ambev" para varias
--   razoes sociais) e descricao de produto ("Coco", "ALHO", "GELO" para
--   produtores pessoa fisica). Sao 470 das 1.155 regras por nome.
--
--   listar_despesas_dia resolve a descricao com
--     coalesce(fornecedor, contraparte_nome, categoria, tipo)
--   ou seja, quando o apelido existe ele SUBSTITUI o nome do extrato na
--   tela. Quem olha o Calendario ve "Coco" e perde de vista que aquele
--   lancamento foi para "Luis Celio Abreu da Silva" -- o dado nao se
--   perde (contraparte_nome continua na base), mas some da leitura, o que
--   atrapalha conferir contra o extrato.
--
-- SOLUCAO
--   Exibir os dois quando forem diferentes: "Coco · Luis Celio Abreu da
--   Silva". Quando o fornecedor apenas repete o nome (620 regras, caso do
--   preenchimento automatico da tela de excecoes), continua saindo so uma
--   vez, sem redundancia.
--
--   A comparacao usa normaliza_nome() nos dois lados, entao diferenca de
--   caixa, acento ou pontuacao ("Fortal Comercial De Gas Ltda" x "FORTAL
--   COMERCIAL DE GAS LTDA") nao gera repeticao na tela.
--
--   Quando um texto esta contido no outro ("Hemile Alexandre" dentro de
--   "HEMILE ALEXANDRE SILVA"), tambem nao repete: sai apenas o mais
--   completo dos dois, que carrega toda a informacao. Os dois lados so
--   aparecem quando sao mesmo nomes distintos -- que e o caso util:
--   "AMBEV · CRBS S/A - CDD FORTALEZA", "B&C · ITALO COMERCIO DE CARNES
--   LTDA", "Coco · Luis Celio Abreu da Silva".
--
--   O agrupamento do ranking de despesas.html NAO muda: la a soma segue
--   por fornecedor, que e justamente o que faz os 25 motoristas somarem
--   num "Uber" so. Agregado agrupa, detalhe identifica.
--
-- OBJETOS
--   ~ public.listar_despesas_dia(date) (create or replace; mesma
--     assinatura, mesmas colunas e tipos)
--
-- RISCO: baixo. Só texto de exibicao; nenhum valor, filtro, regra
--   financeira ou contrato de front-end muda. A coluna descricao continua
--   text e o calendario.html a renderiza como ja fazia.
-- =====================================================================

create or replace function public.listar_despesas_dia(p_dia date)
returns table (descricao text, categoria text, valor numeric)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
begin
  if not public.usuario_pode_acessar_pagina('calendario.html') then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_dia is null then
    raise exception using errcode = '22023', message = 'Dia invalido.';
  end if;

  return query
  with base as (
    select
      f.categoria,
      f.tipo,
      f.valor,
      nullif(btrim(f.fornecedor), '') as forn,
      nullif(btrim(f.contraparte_nome), '') as nome
    from public.fato_financeiro f
    where f.data_caixa = p_dia
      and f.movimentacao = 'Débito'
      and f.empresa = any(array['PRAIA', 'BB']::text[])
      and f.origem is distinct from 'bs_cash'
  ), linhas as (
    select
      case
        when b.forn is null then
          coalesce(b.nome, b.categoria, b.tipo, 'Sem descricao')
        when b.nome is null then b.forn
        -- Um contido no outro (inclusive iguais): so o mais completo.
        when position(public.normaliza_nome(b.forn) in public.normaliza_nome(b.nome)) > 0
          then b.nome
        when position(public.normaliza_nome(b.nome) in public.normaliza_nome(b.forn)) > 0
          then b.forn
        -- Apelido e nome do extrato sao mesmo distintos: mostra os dois.
        else b.forn || ' · ' || b.nome
      end as descricao,
      coalesce(b.categoria, b.tipo, 'Movimentacao de caixa') as categoria,
      round(abs(b.valor), 2) as valor
    from base b

    union all

    select
      'Baixa do dinheiro pendente'::text,
      'Dinheiro em especie'::text,
      round(abs(s.variacao_dinheiro_pendente), 2)
    from public.mv_saldo_caixa_diario_detalhado s
    where s.dia = p_dia
      and s.variacao_dinheiro_pendente < 0
  )
  select l.descricao, l.categoria, l.valor
  from linhas l
  order by l.valor desc, l.descricao;
end;
$function$;

comment on function public.listar_despesas_dia(date) is
  'Saidas bancarias e baixa do dinheiro pendente do Calendario; mostra apelido e nome do extrato quando diferem.';

revoke all privileges on function public.listar_despesas_dia(date)
  from public, anon, authenticated;
grant execute on function public.listar_despesas_dia(date)
  to authenticated;
