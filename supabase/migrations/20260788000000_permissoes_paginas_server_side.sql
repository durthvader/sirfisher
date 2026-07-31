-- Faz a matriz editavel de pagina_permissao valer tambem no banco.
--
-- Problema:
--   o front-end ja bloqueava a navegacao por pagina, mas varias views, RPCs
--   e policies ainda autorizavam papeis fixos. Um usuario autenticado podia
--   chamar a Data API diretamente e ignorar uma restricao configurada na UI.
--
-- Solucao:
--   - helper para endpoints compartilhados por mais de uma pagina;
--   - views app_* das paginas configuraveis consultam pagina_permissao;
--   - RPCs mutaveis e de leitura passam pela mesma autorizacao;
--   - policies das tabelas editaveis acompanham a pagina correspondente.
--
-- O padrao intencional das views e preservado: security_barrier = true e
-- security_invoker = false. A mudanca fica apenas no predicado de acesso.
--
-- Risco:
--   baixo e fail-closed. Se uma pagina nao existir em pagina_permissao, apenas
--   admin continua autorizado. Endpoints compartilhados aceitam acesso quando
--   ao menos uma pagina consumidora estiver liberada; classificacoes recentes
--   e as RPCs de correcao ainda separam excecao de ajuste individual.

begin;

create or replace function public.usuario_pode_acessar_alguma_pagina(
  p_paginas text[]
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select public.usuario_tem_papel(array['admin']::text[])
    or exists (
      select 1
      from public.perfil_usuario pu
      join public.pagina_permissao pp
        on pp.pagina = any(p_paginas)
      where pu.user_id = auth.uid()
        and pu.ativo
        and pu.papel = any(pp.papeis)
    );
$function$;

comment on function public.usuario_pode_acessar_alguma_pagina(text[]) is
  'Autoriza admin ou usuario ativo cujo papel esteja liberado em ao menos uma das paginas informadas.';

revoke all privileges on function public.usuario_pode_acessar_alguma_pagina(text[])
  from public, anon, authenticated;
grant execute on function public.usuario_pode_acessar_alguma_pagina(text[])
  to authenticated;

-- A matriz precisa ser legivel pelo menu dos usuarios liberados, mas uma
-- conta autenticada ainda sem perfil ativo nao precisa enxergar sua estrutura.
drop policy if exists pagina_permissao_leitura on public.pagina_permissao;
create policy pagina_permissao_leitura
  on public.pagina_permissao
  for select
  to authenticated
  using (public.papel_usuario_atual() is not null);

-- Views com um unico predicado de papel. A definicao corrente e reaproveitada
-- para nao duplicar dezenas de consultas financeiras nesta migration.
do $migration$
declare
  v_item record;
  v_view regclass;
  v_definicao text;
  v_paginas_sql text;
  v_substituto text;
  v_ocorrencias integer;
begin
  for v_item in
    select *
    from (values
      ('app_analise_individual',               array['analise_individual.html']::text[]),
      ('app_categoria_dre',                    array['analise_individual.html', 'classificar_excecoes.html']::text[]),
      ('app_conciliacao_stone_resumo_mensal', array['conciliacao.html']::text[]),
      ('app_excecoes',                         array['classificar_excecoes.html']::text[]),
      ('app_gerente_dre_cascata_perc',         array['gerente.html']::text[]),
      ('app_gerente_gasto_grupo',              array['gerente.html']::text[]),
      ('app_gerente_meta_diaria',              array['gerente.html']::text[]),
      ('app_gerente_movimento_hora',           array['gerente.html']::text[]),
      ('app_gerente_resumo_mensal',            array['gerente.html']::text[]),
      ('app_gerente_saldo_variacao',           array['gerente.html']::text[]),
      ('app_gerente_ultima_carga',              array['gerente.html']::text[]),
      ('app_mv_despesa_mensal',                 array['despesas.html']::text[]),
      ('app_painel_cargas',                     array['index.html', 'vendas.html', 'caixa.html', 'dre.html', 'despesas.html']::text[]),
      ('app_painel_composicao_despesa',         array['index.html']::text[]),
      ('app_painel_diario',                     array['index.html', 'vendas.html']::text[]),
      ('app_painel_dre_cascata',                array['index.html', 'dre.html']::text[]),
      ('app_painel_fluxo_caixa',                array['caixa.html']::text[]),
      ('app_painel_margem_contribuicao',        array['index.html']::text[]),
      ('app_painel_recebimento_canal',          array['vendas.html']::text[]),
      ('app_painel_recebimento_hora',           array['vendas.html']::text[]),
      ('app_painel_recebimento_resumo',         array['vendas.html']::text[]),
      ('app_painel_resumo_mensal',              array['index.html', 'vendas.html', 'dre.html', 'despesas.html']::text[]),
      ('app_painel_saldo_atual',                array['index.html', 'caixa.html']::text[]),
      ('app_painel_saldo_fim_mes',              array['index.html', 'caixa.html']::text[]),
      ('app_painel_saldo_por_conta',            array['caixa.html']::text[]),
      ('app_painel_ultima_carga',                array['index.html', 'vendas.html', 'caixa.html', 'dre.html', 'despesas.html']::text[]),
      ('app_projecao_despesa_direta',           array['index.html', 'caixa.html', 'dre.html']::text[]),
      ('app_projecao_despesa_fixa',             array['index.html', 'caixa.html', 'dre.html']::text[]),
      ('app_recebimento_conhecido',             array['caixa.html']::text[]),
      ('app_recebimento_projetado',             array['caixa.html']::text[]),
      ('app_venda_especie_controle',            array['venda_especie.html']::text[])
    ) as mapa(nome, paginas)
  loop
    v_view := to_regclass(format('public.%I', v_item.nome));
    if v_view is null then
      raise exception 'View esperada nao encontrada: public.%', v_item.nome;
    end if;

    v_definicao := pg_get_viewdef(v_view, true);

    if strpos(v_definicao, 'usuario_pode_acessar_alguma_pagina') = 0 then
      select count(*)
        into v_ocorrencias
      from regexp_matches(
        v_definicao,
        '(public\.)?usuario_tem_papel\([^)]*\)',
        'g'
      );

      if v_ocorrencias <> 1 then
        raise exception
          'Predicado de papel inesperado em public.%: % ocorrencias',
          v_item.nome,
          v_ocorrencias;
      end if;

      select string_agg(quote_literal(pagina), ', ' order by ordem)
        into v_paginas_sql
      from unnest(v_item.paginas) with ordinality as p(pagina, ordem);

      v_substituto := format(
        'public.usuario_pode_acessar_alguma_pagina(array[%s]::text[])',
        v_paginas_sql
      );
      v_definicao := regexp_replace(
        v_definicao,
        '(public\.)?usuario_tem_papel\([^)]*\)',
        v_substituto,
        'g'
      );

      execute format(
        'create or replace view public.%I with (security_barrier = true, security_invoker = false) as %s',
        v_item.nome,
        v_definicao
      );
    end if;

    execute format(
      'revoke all privileges on public.%I from public, anon, authenticated',
      v_item.nome
    );
    execute format(
      'grant select on public.%I to authenticated',
      v_item.nome
    );
  end loop;
end;
$migration$;

-- A view compartilhada de historico possui dois ramos. Cada ramo obedece a
-- pagina que realmente permite operar aquele tipo de classificacao.
create or replace view public.app_classificacoes_recentes
with (security_barrier = true, security_invoker = false) as
select
  'excecao'::text as tipo,
  d.id::bigint as id,
  coalesce(d.fornecedor, d.chave_valor) as titulo,
  case d.chave_tipo when 'cnpj' then 'Regra por CNPJ' else 'Regra por nome' end as detalhe,
  d.categoria,
  c.natureza,
  d.atualizado_em as quando,
  null::date as data_lancamento,
  null::numeric as valor
from public.de_para d
left join public.categoria_dre c on c.categoria = d.categoria
where d.ativo
  and public.usuario_pode_acessar_pagina('classificar_excecoes.html')

union all

select
  'individual'::text as tipo,
  a.id::bigint as id,
  coalesce(f.contraparte_nome, f.fornecedor, a.origem || ' #' || a.raw_id::text) as titulo,
  'Transacao individual'::text as detalhe,
  a.categoria,
  f.natureza,
  a.criado_em as quando,
  f.data_caixa as data_lancamento,
  f.valor
from public.ajuste_manual a
left join public.fato_financeiro f
  on f.origem = a.origem and f.raw_id = a.raw_id
where public.usuario_pode_acessar_pagina('analise_individual.html');

revoke all privileges on public.app_classificacoes_recentes
  from public, anon, authenticated;
grant select on public.app_classificacoes_recentes to authenticated;

-- Funcoes usadas por views security_invoker e RPCs chamadas pelo navegador.
-- pg_get_functiondef preserva integralmente os corpos atuais e troca somente
-- o predicado de papel, falhando se a estrutura esperada tiver divergido.
do $migration$
declare
  v_item record;
  v_funcoes oid[];
  v_oid oid;
  v_definicao text;
  v_assinatura text;
  v_ocorrencias integer;
begin
  for v_item in
    select *
    from (values
      (
        'private',
        'ler_conciliacao_stone',
        $expr$public.usuario_pode_acessar_pagina('conciliacao.html')$expr$
      ),
      (
        'private',
        'ler_conciliacao_stone_resumo',
        $expr$public.usuario_pode_acessar_pagina('conciliacao.html')$expr$
      ),
      (
        'private',
        'ler_painel_meta_real_mensal',
        $expr$public.usuario_pode_acessar_pagina('planejamento.html')$expr$
      ),
      (
        'public',
        'classificar_transacao',
        $expr$public.usuario_pode_acessar_pagina('analise_individual.html')$expr$
      ),
      (
        'public',
        'classificar_excecao',
        $expr$public.usuario_pode_acessar_pagina('classificar_excecoes.html')$expr$
      ),
      (
        'public',
        'corrigir_classificacao',
        $expr$coalesce(
          (p_tipo = 'excecao' and public.usuario_pode_acessar_pagina('classificar_excecoes.html'))
          or
          (p_tipo = 'individual' and public.usuario_pode_acessar_pagina('analise_individual.html')),
          false
        )$expr$
      ),
      (
        'public',
        'desfazer_classificacao',
        $expr$coalesce(
          (p_tipo = 'excecao' and public.usuario_pode_acessar_pagina('classificar_excecoes.html'))
          or
          (p_tipo = 'individual' and public.usuario_pode_acessar_pagina('analise_individual.html')),
          false
        )$expr$
      ),
      (
        'public',
        'listar_ranking_fornecedor',
        $expr$public.usuario_pode_acessar_pagina('despesas.html')$expr$
      ),
      (
        'public',
        'salvar_sangria',
        $expr$public.usuario_pode_acessar_pagina('venda_especie.html')$expr$
      ),
      (
        'public',
        'alterar_status_sangria',
        $expr$public.usuario_pode_acessar_pagina('venda_especie.html')$expr$
      )
    ) as mapa(esquema, nome, autorizacao)
  loop
    select array_agg(p.oid order by p.oid)
      into v_funcoes
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = v_item.esquema
      and p.proname = v_item.nome
      and p.prokind = 'f';

    if coalesce(cardinality(v_funcoes), 0) <> 1 then
      raise exception
        'Esperada uma funcao %.%, encontradas %',
        v_item.esquema,
        v_item.nome,
        coalesce(cardinality(v_funcoes), 0);
    end if;

    v_oid := v_funcoes[1];
    v_definicao := pg_get_functiondef(v_oid);
    v_assinatura := pg_get_function_identity_arguments(v_oid);

    if strpos(v_definicao, 'usuario_pode_acessar_pagina') = 0
       and strpos(v_definicao, 'usuario_pode_acessar_alguma_pagina') = 0 then
      select count(*)
        into v_ocorrencias
      from regexp_matches(
        v_definicao,
        '(public\.)?usuario_tem_papel\([^)]*\)',
        'g'
      );

      if v_ocorrencias <> 1 then
        raise exception
          'Predicado de papel inesperado em %.%: % ocorrencias',
          v_item.esquema,
          v_item.nome,
          v_ocorrencias;
      end if;

      v_definicao := regexp_replace(
        v_definicao,
        '(public\.)?usuario_tem_papel\([^)]*\)',
        v_item.autorizacao,
        'g'
      );
      execute v_definicao;
    end if;

    execute format(
      'revoke all privileges on function %I.%I(%s) from public, anon, authenticated',
      v_item.esquema,
      v_item.nome,
      v_assinatura
    );
    execute format(
      'grant execute on function %I.%I(%s) to authenticated',
      v_item.esquema,
      v_item.nome,
      v_assinatura
    );
  end loop;
end;
$migration$;

-- Impede que as permissoes por papel antigas sejam usadas para escrever nas
-- tabelas diretamente, contornando as RPCs protegidas acima.
drop policy if exists ajuste_auth_sel on public.ajuste_manual;
drop policy if exists ajuste_auth_ins on public.ajuste_manual;
drop policy if exists ajuste_auth_upd on public.ajuste_manual;

create policy ajuste_auth_sel
  on public.ajuste_manual
  for select
  to authenticated
  using (public.usuario_pode_acessar_pagina('analise_individual.html'));

create policy ajuste_auth_ins
  on public.ajuste_manual
  for insert
  to authenticated
  with check (public.usuario_pode_acessar_pagina('analise_individual.html'));

create policy ajuste_auth_upd
  on public.ajuste_manual
  for update
  to authenticated
  using (public.usuario_pode_acessar_pagina('analise_individual.html'))
  with check (public.usuario_pode_acessar_pagina('analise_individual.html'));

drop policy if exists de_para_auth_ins on public.de_para;
create policy de_para_auth_ins
  on public.de_para
  for insert
  to authenticated
  with check (public.usuario_pode_acessar_pagina('classificar_excecoes.html'));

drop policy if exists venda_especie_auth_sel on public.venda_especie;
drop policy if exists venda_especie_auth_ins on public.venda_especie;
drop policy if exists venda_especie_auth_upd on public.venda_especie;

create policy venda_especie_auth_sel
  on public.venda_especie
  for select
  to authenticated
  using (public.usuario_pode_acessar_pagina('venda_especie.html'));

create policy venda_especie_auth_ins
  on public.venda_especie
  for insert
  to authenticated
  with check (public.usuario_pode_acessar_pagina('venda_especie.html'));

create policy venda_especie_auth_upd
  on public.venda_especie
  for update
  to authenticated
  using (public.usuario_pode_acessar_pagina('venda_especie.html'))
  with check (public.usuario_pode_acessar_pagina('venda_especie.html'));

commit;
