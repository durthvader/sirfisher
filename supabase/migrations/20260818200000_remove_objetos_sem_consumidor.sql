-- =====================================================================
-- Remove objetos sem consumidor confirmado
-- =====================================================================
--
-- MOTIVO
--   Revisão geral do projeto. Cada objeto abaixo foi confirmado morto por
--   três evidências independentes, cruzadas no catálogo e no repositório:
--
--     1. nenhuma view ou materialized view depende dele (pg_depend);
--     2. nenhuma função de `public` ou `private` o cita
--        (pg_get_functiondef com limite de palavra);
--     3. nenhuma referência exata no código ativo -- páginas HTML, `assets/`,
--        scripts de importação e scripts de CI -- desconsiderando migrations
--        e documentação, que registram o histórico.
--
--   Todos têm ACL apenas para `postgres` e `service_role`: nunca foram
--   expostos a `anon` nem a `authenticated`, então não existe consumidor
--   externo possível pela Data API.
--
--   O caso que motivou a revisão foi `mv_saldo_caixa_diario_detalhado`.
--   Aposentada em 20260818120000, ela continuou no banco congelada no último
--   refresh anterior (11/08/2026), enquanto `corte_caixa` seguia avançando.
--   Em 14/08/2026 esse dado velho foi lido como se fosse atual e levou a um
--   diagnóstico errado de painel desatualizado (ver 20260818190000). Dado
--   parado que aparenta estar vivo é pior do que objeto ausente.
--
-- REMOVIDOS
--   ~ public.mv_saldo_caixa_diario_detalhado  -- MV aposentada em 20260818120000
--   ~ public.painel_dre_executivo             -- sem consumidor desde o
--   ~ public.painel_tendencia_diaria             inventário de 2026-07-03
--   ~ public.painel_venda_mes_atual              (docs/OBJETOS_SEM_CONSUMIDOR.md);
--   ~ public.saldo_mensal                        janela de observação cumprida
--   ~ public.saldo_stone_atual                   e remoção autorizada
--   ~ public.vendas_diaria
--   ~ public.app_gerenciador_de_para          -- a página usa listar_regras_de_para
--   ~ public.detalhar_saldo_caixa_dia(date)   -- substituída por
--                                                listar_saldo_contas_dia(date)
--   ~ public.importar_contas_recorrentes_legado(jsonb, jsonb)
--   ~ public.admin_salvar_conta(...)                     -- sobrecargas antigas,
--   ~ public.admin_salvar_fonte_financeira(...)             substituídas por
--   ~ public.admin_salvar_fonte_financeira_com_saldo(...)    _com_saldo e
--                                                            _com_vigencia
--
--   As três últimas e `importar_contas_recorrentes_legado` estavam com
--   `execute` para `authenticated` sem nenhum chamador -- superfície exposta
--   sem uso. `importar_contas_recorrentes_legado` ainda escrevia em massa.
--
-- PRESERVADOS DE PROPÓSITO
--   - `conciliacao_stone_resumo`, `private.ler_conciliacao_stone_resumo` e
--     `app_conciliacao_stone_resumo`: sem consumidor hoje, mas
--     docs/OBJETOS_SEM_CONSUMIDOR.md manda preservar enquanto a fase de
--     conciliação estiver no roadmap.
--   - `backup_grants_20260629` e `backup_policies_20260629`: guardam o estado
--     de permissões antes da operação de segurança de 2026-06-29. São dados,
--     não derivados -- não dá para recriar. Removê-las exige decisão à parte.
--   - `painel_colchao_despesa_fixa`: sem consumidor no front-end, mas é a
--     memória de cálculo de `projecao_despesa_fixa` e serve ao diagnóstico
--     dela. Mantida e marcada como diagnóstica no comentário do objeto.
--   - `admin_listar_saldo_inicial` / `admin_salvar_saldo_inicial`: a tabela
--     `saldo_inicial` continua viva (tem view dependente e função que a lê),
--     então as RPCs ficam até a decisão sobre a própria tabela.
--
-- RISCO: baixo, e a migration se recusa a rodar se algo mudou.
--   - Nenhum dado financeiro é tocado. As views são derivadas e a MV é
--     recomputável; todas as definições seguem no histórico de migrations.
--   - `drop` sem `cascade`: se qualquer objeto tiver ganhado dependente
--     desde a auditoria, o comando falha e a transação inteira volta atrás.
--   - A verificação prévia aborta antes de qualquer `drop` se aparecer
--     dependência de view/MV ou citação em função.
-- =====================================================================

begin;

-- Reconfere no banco, não na auditoria: se algum alvo ganhou consumidor
-- desde então, nada é removido.
do $verificacao$
declare
  v_alvo text;
  v_oid oid;
  v_dependentes integer;
  v_funcoes integer;
begin
  foreach v_alvo in array array[
    'mv_saldo_caixa_diario_detalhado',
    'painel_dre_executivo',
    'painel_tendencia_diaria',
    'painel_venda_mes_atual',
    'saldo_mensal',
    'saldo_stone_atual',
    'vendas_diaria',
    'app_gerenciador_de_para'
  ] loop
    v_oid := to_regclass('public.' || v_alvo);
    if v_oid is null then
      continue;  -- já removido: migration re-executável
    end if;

    select count(*) into v_dependentes
    from pg_depend d
    join pg_rewrite r on r.oid = d.objid
    join pg_class c on c.oid = r.ev_class
    where d.refobjid = v_oid and c.oid <> v_oid;

    select count(*) into v_funcoes
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ~ ('\m' || v_alvo || '\M');

    if v_dependentes > 0 or v_funcoes > 0 then
      raise exception
        'public.% ganhou consumidor (views=%, funcoes=%); remocao cancelada.',
        v_alvo, v_dependentes, v_funcoes;
    end if;
  end loop;
end;
$verificacao$;

drop materialized view if exists public.mv_saldo_caixa_diario_detalhado;

drop view if exists public.painel_dre_executivo;
drop view if exists public.painel_tendencia_diaria;
drop view if exists public.painel_venda_mes_atual;
drop view if exists public.saldo_mensal;
drop view if exists public.saldo_stone_atual;
drop view if exists public.vendas_diaria;
drop view if exists public.app_gerenciador_de_para;

drop function if exists public.detalhar_saldo_caixa_dia(date);
drop function if exists public.importar_contas_recorrentes_legado(jsonb, jsonb);
drop function if exists public.admin_salvar_conta(
  smallint, text, text, smallint, boolean
);
drop function if exists public.admin_salvar_fonte_financeira(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean
);
drop function if exists public.admin_salvar_fonte_financeira_com_saldo(
  text, text, smallint, boolean, boolean, boolean, boolean, boolean, text
);

comment on view public.painel_colchao_despesa_fixa is
  'Memória de cálculo mensal da projeção de despesa fixa; usa a mesma regra de corte de caixa da projeção diária. Objeto de diagnóstico: sem consumidor no front-end de propósito, serve para conferir a projeção quando ela divergir.';

-- O que a aplicação usa de verdade tem de continuar de pé.
do $validacao$
declare
  v_faltando text[] := array[]::text[];
  v_nome text;
begin
  foreach v_nome in array array[
    'app_painel_fluxo_caixa',
    'app_painel_saldo_atual',
    'app_painel_saldo_por_conta',
    'app_gerenciador_de_para_historico',
    'app_conciliacao_stone_resumo',
    'projecao_despesa_fixa',
    'projecao_despesa_direta',
    'painel_colchao_despesa_fixa',
    'painel_fluxo_caixa',
    'conciliacao_stone_resumo',
    'saldo_inicial'
  ] loop
    if to_regclass('public.' || v_nome) is null then
      v_faltando := v_faltando || v_nome;
    end if;
  end loop;

  if array_length(v_faltando, 1) is not null then
    raise exception 'Objeto em uso desapareceu: %.', array_to_string(v_faltando, ', ');
  end if;

  -- Confere por nome, não por assinatura: o objetivo é garantir que a RPC
  -- continua existindo, sem prender a validação à lista de argumentos.
  foreach v_nome in array array[
    'listar_saldo_contas_dia',
    'listar_calendario_financeiro',
    'listar_despesas_dia',
    'resumo_corte_caixa',
    'admin_salvar_conta_com_saldo',
    'admin_salvar_fonte_financeira_com_vigencia',
    'listar_regras_de_para'
  ] loop
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = v_nome
        and has_function_privilege('authenticated', p.oid, 'execute')
    ) then
      raise exception 'RPC em uso desapareceu ou perdeu o grant: %.', v_nome;
    end if;
  end loop;

  if to_regclass('public.mv_saldo_caixa_diario_detalhado') is not null then
    raise exception 'A materialized view aposentada continua no banco.';
  end if;
end;
$validacao$;

commit;
