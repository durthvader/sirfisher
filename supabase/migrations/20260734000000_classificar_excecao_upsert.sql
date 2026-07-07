-- =====================================================================
-- classificar_excecao: INSERT vira upsert para nao estourar chave unica
-- =====================================================================
--
-- Bug reportado pelo usuario: ao salvar uma classificacao em
-- classificar_excecoes.html (ex: "ROGERIO LUIZ DA FONSECA"), o painel
-- devolve "duplicate key value violates unique constraint
-- de_para_chave_tipo_chave_valor_key".
--
-- Causa: de_para tem UNIQUE (chave_tipo, chave_valor) e a funcao
-- classificar_excecao (migration 20260716) faz INSERT puro. Quando a
-- contraparte ja tem uma regra na tabela (por exemplo uma regra antiga,
-- inativa, ou 'ANALISAR INDIVIDUAL'), o segundo INSERT viola a
-- constraint e nada e salvo.
--
-- Correcao: ON CONFLICT (chave_tipo, chave_valor) DO UPDATE, atualizando
-- categoria/fornecedor, reativando a linha (ativo = true) e marcando
-- atualizado_em. E o mesmo destino que a view de_para_u ja le (uma linha
-- ativa por chave), entao o comportamento das telas nao muda — apenas o
-- salvamento passa a funcionar tambem quando a chave ja existe.
--
-- Risco: baixo. So a funcao e recriada (create or replace); nenhuma
-- linha existente e apagada. A unica mudanca de comportamento e que
-- salvar por cima de uma regra existente agora a substitui em vez de
-- falhar — que e exatamente o que o usuario espera ao classificar.
-- =====================================================================

begin;

create or replace function public.classificar_excecao(
  p_chave_tipo text,
  p_chave_valor text,
  p_fornecedor text,
  p_categoria text
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id bigint;
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  if not exists (select 1 from public.categoria_dre c where c.categoria = p_categoria) then
    raise exception using errcode = '22023', message = 'Categoria invalida.';
  end if;

  insert into public.de_para (chave_tipo, chave_valor, fornecedor, categoria, ativo, atualizado_em)
  values (p_chave_tipo, p_chave_valor, p_fornecedor, p_categoria, true, now())
  on conflict (chave_tipo, chave_valor) do update
    set fornecedor = excluded.fornecedor,
        categoria = excluded.categoria,
        ativo = true,
        atualizado_em = now()
  returning id::bigint into v_id;

  return v_id;
end;
$function$;

commit;
