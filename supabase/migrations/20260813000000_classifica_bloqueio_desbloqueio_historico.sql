-- =====================================================================
-- Fecha a excecao "Desconhecido / Valor Desbloqueado" do historico
-- =====================================================================
--
-- PROBLEMA
--   A tela classificar_excecoes.html mostrava uma pendencia fixa:
--   contraparte "Desconhecido", tipo "Valor Desbloqueado", 2 lancamentos,
--   +R$ 84,61 (18 e 19/11/2025, origem historico). Salvar a classificacao
--   nao fazia ela sumir, por mais vezes que fosse feito.
--
--   Sao tres camadas empilhadas:
--
--   1. A regra ja existia em de_para (chave nome/DESCONHECIDO), ativa
--      desde 03/08/2026. O botao Salvar funcionava; a regra e que nao era
--      aplicada em lugar nenhum.
--
--   2. Para origem='historico', a view fato_financeiro nao consulta
--      de_para -- o status sai so de raw_historico.categoria (o join foi
--      removido em 20260730000000 por causar timeout). Classificar pela
--      tela nunca reclassifica o historico sozinho; depende da RPC
--      sincronizar_historico_de_para() (botao em status.html).
--
--   3. E essa RPC descarta de proposito a chave por nome quando a
--      contraparte se chama "Desconhecido"
--      (20260732000000, `when c.contraparte_nome ilike 'desconhecido'
--      then null`) -- mesma protecao que a propria fato_financeiro aplica
--      nas fontes vivas. Como contraparte_doc tambem e o texto
--      "Desconhecido" (nao e CNPJ), a unica chave possivel e a de nome, ou
--      seja: a regra e ignorada em todos os caminhos e a excecao voltava
--      para sempre.
--
--   A protecao do item 3 esta certa: "Desconhecido" e um rotulo generico
--   que aparece em 8.942 lancamentos (historico + Stone) de contrapartes
--   completamente diferentes. Agrupar tudo isso sob uma regra so seria
--   pior que a pendencia. Portanto a correcao e pontual nas linhas, nao
--   no de_para.
--
-- O QUE SAO ESSAS LINHAS
--   Sao pares de bloqueio/desbloqueio de valor da Stone, no mesmo dia e
--   com o mesmo valor absoluto -- efeito liquido zero no caixa:
--     44738  18/11/2025  Valor Bloqueado     -61,71
--     44739  18/11/2025  Valor Desbloqueado  +61,71
--     44749  19/11/2025  Valor Bloqueado     -22,90
--     44750  19/11/2025  Valor Desbloqueado  +22,90
--
--   Os tres pares anteriores do mesmo tipo (2021-12-07, 2025-07-02 e
--   2025-07-11) ja estao classificados como 'estornado' (CONTABIL). Esta
--   migration apenas repete essa classificacao nos pares que ficaram para
--   tras: os creditos estavam com categoria nula (a excecao da tela) e os
--   debitos com 'ANALISAR INDIVIDUAL'.
--
-- OBJETOS
--   ~ public.raw_historico  -- UPDATE em 4 linhas (categoria, dre_grupo)
--   ~ public.de_para        -- desativa a regra inerte nome/DESCONHECIDO
--
-- RISCO: baixo.
--   - 'estornado' tem dre_grupo CONTABIL, que 20260748000000 exclui do
--     DRE. Nenhum numero de DRE, caixa ou faturamento muda; o par ja era
--     neutro (soma zero). O efeito e a pendencia sumir da tela.
--   - O UPDATE e restrito a tipo Valor Bloqueado/Desbloqueado com
--     categoria nula ou 'ANALISAR INDIVIDUAL' -- nao toca no que ja esta
--     classificado e e re-executavel sem efeito adicional.
--   - A regra de_para nome/DESCONHECIDO e ignorada por fato_financeiro e
--     por sincronizar_historico_de_para(), entao desativa-la nao muda
--     nenhuma classificacao existente. Serve para tirar do Gerenciador
--     De/Para uma regra que nunca teve efeito e induz a erro.
-- =====================================================================

begin;

update public.raw_historico rh
set categoria = 'estornado',
    dre_grupo = cd.dre_grupo
from public.categoria_dre cd
where cd.categoria = 'estornado'
  and rh.tipo in ('Valor Bloqueado', 'Valor Desbloqueado')
  and (rh.categoria is null or rh.categoria = 'ANALISAR INDIVIDUAL');

update public.de_para
set ativo = false,
    atualizado_em = now()
where chave_tipo = 'nome'
  and chave_valor = 'DESCONHECIDO'
  and ativo;

commit;
