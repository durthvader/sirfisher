-- Permite que despesas.html use a mesma memoria prospectiva do Resumo,
-- Caixa e DRE. A mudanca amplia somente o gate por pagina das duas views;
-- nao altera as projecoes, os lancamentos ou as classificacoes financeiras.

begin;

create or replace view public.app_projecao_despesa_direta
with (security_barrier = true, security_invoker = false) as
select s.dia, s.valor
from public.projecao_despesa_direta s
where public.usuario_pode_acessar_alguma_pagina(array[
  'index.html', 'caixa.html', 'dre.html', 'despesas.html'
]);

create or replace view public.app_projecao_despesa_fixa
with (security_barrier = true, security_invoker = false) as
select s.dia, s.valor
from public.projecao_despesa_fixa s
where public.usuario_pode_acessar_alguma_pagina(array[
  'index.html', 'caixa.html', 'dre.html', 'despesas.html'
]);

comment on view public.app_projecao_despesa_direta is
  'Projecao de despesa direta disponivel ao Resumo, Caixa, DRE e Despesas conforme permissao configurada por pagina.';

comment on view public.app_projecao_despesa_fixa is
  'Projecao de despesa fixa disponivel ao Resumo, Caixa, DRE e Despesas conforme permissao configurada por pagina.';

commit;
