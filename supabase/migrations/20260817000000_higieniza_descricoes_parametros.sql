-- Remove valores circunstanciais dos titulos de parametros editaveis.
-- Altera somente descricao; valores e regras financeiras permanecem iguais.

update public.parametros as p
set descricao = v.descricao
from (
  values
    ('dias_provisao_estoque'::text, 'Dias entre a venda e a reposição'::text),
    ('perc_despesa_direta'::text, 'Despesa direta por real vendido'::text)
) as v(chave, descricao)
where p.chave = v.chave
  and p.descricao is distinct from v.descricao;
