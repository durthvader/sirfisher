-- Classifica como "Transferencia entre Contas" as linhas do historico legado
-- (raw_historico) ainda sem categoria cuja contraparte é o CNPJ do BS
-- Instituição de Pagamento S/A (40.994.589/0001-05).
--
-- Contexto: esse mesmo CNPJ já foi corrigido em de_para para
-- 'Transferencia entre Contas' (ver 20260726000000_classifica_bs_cash_e_
-- corrige_transferencia.sql), mas a view fato_financeiro não consulta
-- de_para para origem='historico' — ela usa categoria/dre_grupo já
-- congeladas na importação da planilha. Por isso essas linhas continuavam
-- em status='excecao' mesmo depois daquela correção.
--
-- Escopo: só linhas ainda SEM categoria (as que hoje aparecem como exceção).
-- Linhas do histórico com esse mesmo CNPJ que já tenham alguma categoria
-- definida (ex.: "Folha Salarial", herdada do mesmo erro original) não são
-- tocadas aqui — ficam para uma revisão separada, já que reclassificar dado
-- que já estava "fechado" tem um impacto retroativo maior.
--
-- destino_documento/origem_documento guardam o CNPJ/CPF formatado (ou
-- mascarado, ex. "***.123.456-**"); segue o mesmo guard usado no resto do
-- projeto (so_digitos só quando o documento não está mascarado) antes de
-- comparar.

update public.raw_historico
set categoria = 'Transferencia entre Contas',
    dre_grupo = 'TRANSFERENCIA'
where categoria is null
  and (case when movimentacao = 'Débito' then destino_documento else origem_documento end)
      like '%/%'
  and (case when movimentacao = 'Débito' then destino_documento else origem_documento end)
      not like '%*%'
  and so_digitos(
        case when movimentacao = 'Débito' then destino_documento else origem_documento end
      ) = '40994589000105';
