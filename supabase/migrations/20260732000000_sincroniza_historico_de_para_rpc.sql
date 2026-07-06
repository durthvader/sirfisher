-- =====================================================================
-- RPC admin: sincroniza historico sem categoria com o DE-Para atual
-- =====================================================================
--
-- CONTEXTO
--   20260731 resolveu, uma unica vez, as linhas de raw_historico sem
--   categoria que ja tinham regra em de_para. Como a view fato_financeiro
--   nao consulta de_para para origem='historico' (revertido em 20260730
--   por causar timeout), cadastrar um fornecedor novo em
--   classificar_excecoes.html nao reclassifica automaticamente o
--   historico -- e preciso rodar esse mesmo UPDATE de novo.
--
--   Em vez de exigir uma migration nova a cada rodada, esta funcao expoe o
--   mesmo UPDATE como RPC sob demanda, no mesmo padrao de
--   solicitar_refresh_painel (20260719000000): SECURITY DEFINER, restrita
--   a admin, chamavel pela tela.
--
-- OBJETOS
--   + public.sincronizar_historico_de_para() -- nova funcao SECURITY DEFINER
--
-- RISCO: baixo.
--   - So afeta linhas de raw_historico com categoria is null (nunca
--     reclassifica o que ja esta congelado).
--   - Ignora match com categoria magica 'ANALISAR INDIVIDUAL' (raw_historico
--     nao tem coluna de status para representar esse fluxo).
--   - Escopo limitado (so linhas nulas), mesmo raciocinio de custo que
--     20260731 -- nao reintroduz o join de toda a tabela a cada leitura que
--     causou o timeout em 20260729.
-- =====================================================================

begin;

create or replace function public.sincronizar_historico_de_para()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  linhas_afetadas integer;
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores podem sincronizar o histórico.';
  end if;

  with de_para_ativo as (
    select distinct on (chave_tipo, chave_valor)
      chave_tipo, chave_valor, categoria, fornecedor
    from public.de_para
    where ativo
    order by chave_tipo, chave_valor, id desc
  ),
  candidatos as (
    select
      h.id,
      case when h.movimentacao = 'Débito' then h.destino_documento else h.origem_documento end as contraparte_doc,
      case when h.movimentacao = 'Débito' then h.destino else h.origem end as contraparte_nome
    from public.raw_historico h
    where h.categoria is null
  ),
  resolvido as (
    select
      c.id,
      coalesce(dpc.categoria, dpn.categoria) as categoria,
      coalesce(dpc.fornecedor, dpn.fornecedor) as fornecedor
    from candidatos c
    left join de_para_ativo dpc
      on dpc.chave_tipo = 'cnpj'
     and dpc.chave_valor = case
       when c.contraparte_doc like '%/%' and c.contraparte_doc not like '%*%' then public.so_digitos(c.contraparte_doc)
       else null
     end
    left join de_para_ativo dpn
      on dpn.chave_tipo = 'nome'
     and dpn.chave_valor = case
       when c.contraparte_nome ilike 'desconhecido' then null
       else public.normaliza_nome(c.contraparte_nome)
     end
    where coalesce(dpc.categoria, dpn.categoria) is not null
      and coalesce(dpc.categoria, dpn.categoria) <> 'ANALISAR INDIVIDUAL'
  )
  update public.raw_historico rh
  set categoria = r.categoria,
      dre_grupo = cd.dre_grupo,
      fornecedor = coalesce(rh.fornecedor, r.fornecedor)
  from resolvido r
  left join public.categoria_dre cd on cd.categoria = r.categoria
  where rh.id = r.id;

  get diagnostics linhas_afetadas = row_count;

  return linhas_afetadas;
end;
$$;

revoke all privileges on function public.sincronizar_historico_de_para() from public, anon, authenticated;
grant execute on function public.sincronizar_historico_de_para() to authenticated;

commit;
