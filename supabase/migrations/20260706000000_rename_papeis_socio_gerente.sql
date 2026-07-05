-- Rename de papeis: gestor -> socio, operador -> gerente.
-- Nao muda nenhuma regra de acesso, apenas o nome interno do papel.
-- O papel admin permanece inalterado.
--
-- Objetos afetados (levantados via consulta ao banco linkado antes desta
-- migration): constraint de perfil_usuario, dados existentes, 2 funcoes RPC,
-- 7 RLS policies (ajuste_manual, venda_especie, de_para) e 22 views
-- financeiras que checam papel via usuario_tem_papel(text[]).

begin;

-- 1. Solta a constraint antiga (os dados ainda tem os valores antigos aqui).
alter table public.perfil_usuario
  drop constraint perfil_usuario_papel_check;

-- 2. Dados existentes.
update public.perfil_usuario
   set papel = case papel when 'gestor' then 'socio' when 'operador' then 'gerente' else papel end
 where papel in ('gestor', 'operador');

update public.pagina_permissao
   set papeis = array_replace(array_replace(papeis, 'gestor', 'socio'), 'operador', 'gerente')
 where papeis && array['gestor', 'operador'];

-- Constraint nova, so depois que os dados ja estao no formato novo.
alter table public.perfil_usuario
  add constraint perfil_usuario_papel_check check (papel in ('admin', 'socio', 'gerente'));

-- 3. Funcoes RPC que validam o papel.
create or replace function public.definir_acesso_usuario(p_user_id uuid, p_papel text, p_ativo boolean default true)
 returns table(user_id uuid, email text, papel text, ativo boolean)
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
    v_papel_atual text;
    v_ativo_atual boolean;
    v_admins_ativos integer;
begin
    if not public.usuario_tem_papel(array['admin']::text[]) then
        raise exception using errcode = '42501', message = 'Apenas administradores podem alterar acessos.';
    end if;

    if p_papel is null or p_papel not in ('admin', 'socio', 'gerente') then
        raise exception using errcode = '22023', message = 'Papel invalido.';
    end if;

    if not exists (select 1 from auth.users u where u.id = p_user_id) then
        raise exception using errcode = '22023', message = 'Usuario nao encontrado.';
    end if;

    lock table public.perfil_usuario in share row exclusive mode;

    select p.papel, p.ativo
        into v_papel_atual, v_ativo_atual
    from public.perfil_usuario p
    where p.user_id = p_user_id;

    if v_papel_atual = 'admin'
          and v_ativo_atual
          and (p_papel <> 'admin' or not p_ativo) then
        select count(*)::integer
            into v_admins_ativos
        from public.perfil_usuario p
        where p.papel = 'admin' and p.ativo;

        if v_admins_ativos <= 1 then
            raise exception using errcode = '23514', message = 'Nao e possivel remover o ultimo administrador ativo.';
        end if;
    end if;

    insert into public.perfil_usuario (user_id, papel, ativo)
    values (p_user_id, p_papel, p_ativo)
    on conflict on constraint perfil_usuario_pkey do update
        set papel = excluded.papel,
            ativo = excluded.ativo;

    return query
    select u.id, u.email::text, p.papel, p.ativo
    from auth.users u
    join public.perfil_usuario p on p.user_id = u.id
    where u.id = p_user_id;
end;
$function$;

create or replace function public.definir_permissao_pagina(p_pagina text, p_papeis text[])
 returns table(pagina text, papeis text[])
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
    v_papeis_validos text[] := array['socio', 'gerente'];
    v_pagina_valida boolean;
begin
    if not public.usuario_tem_papel(array['admin']::text[]) then
        raise exception using errcode = '42501', message = 'Apenas administradores podem alterar permissoes.';
    end if;

    select exists(select 1 from public.pagina_permissao pp where pp.pagina = p_pagina)
        into v_pagina_valida;

    if not v_pagina_valida then
        raise exception using errcode = '22023', message = 'Pagina desconhecida.';
    end if;

    if p_papeis is null or not (p_papeis <@ v_papeis_validos) then
        raise exception using errcode = '22023', message = 'Papel invalido. Use apenas socio e/ou gerente.';
    end if;

    update public.pagina_permissao pp
    set papeis = p_papeis, atualizado_em = now()
    where pp.pagina = p_pagina;

    return query
    select pp.pagina, pp.papeis
    from public.pagina_permissao pp
    where pp.pagina = p_pagina;
end;
$function$;

-- 4. RLS policies com papel literal.
alter policy ajuste_auth_ins on public.ajuste_manual
  with check (usuario_tem_papel(array['admin', 'socio', 'gerente']));

alter policy ajuste_auth_sel on public.ajuste_manual
  using (usuario_tem_papel(array['admin', 'socio', 'gerente']));

alter policy ajuste_auth_upd on public.ajuste_manual
  using (usuario_tem_papel(array['admin', 'socio', 'gerente']))
  with check (usuario_tem_papel(array['admin', 'socio', 'gerente']));

alter policy venda_especie_auth_ins on public.venda_especie
  with check (usuario_tem_papel(array['admin', 'socio', 'gerente']));

alter policy venda_especie_auth_sel on public.venda_especie
  using (usuario_tem_papel(array['admin', 'socio', 'gerente']));

alter policy venda_especie_auth_upd on public.venda_especie
  using (usuario_tem_papel(array['admin', 'socio', 'gerente']))
  with check (usuario_tem_papel(array['admin', 'socio', 'gerente']));

alter policy de_para_auth_ins on public.de_para
  with check (usuario_tem_papel(array['admin', 'socio', 'gerente']));

-- 5. Views financeiras (admin+socio, exceto as 3 que tambem liberam gerente).
create or replace view public.app_analise_individual with (security_barrier=true, security_invoker=false) as
  select origem, raw_id, empresa, unidade, data_caixa, movimentacao, natureza, valor,
         contraparte_nome, contraparte_doc, fornecedor
  from analise_individual s
  where usuario_tem_papel(array['admin', 'socio', 'gerente']);

create or replace view public.app_categoria_dre with (security_barrier=true, security_invoker=false) as
  select categoria, dre_grupo, natureza
  from categoria_dre s
  where usuario_tem_papel(array['admin', 'socio', 'gerente']);

create or replace view public.app_excecoes with (security_barrier=true, security_invoker=false) as
  select contraparte_nome, contraparte_doc, chave_tipo, chave_valor, qtd_lancamentos, total,
         natureza, data_min, data_max
  from excecoes s
  where usuario_tem_papel(array['admin', 'socio', 'gerente']);

create or replace view public.app_mv_despesa_mensal with (security_barrier=true, security_invoker=false) as
  select mes, ano_mes, grupo, categoria, fornecedor, valor, lancamentos
  from mv_despesa_mensal s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_cargas with (security_barrier=true, security_invoker=false) as
  select quando, fontes
  from painel_cargas s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_composicao_despesa with (security_barrier=true, security_invoker=false) as
  select mes, ano_mes, grupo, valor
  from painel_composicao_despesa s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_diario with (security_barrier=true, security_invoker=false) as
  select dia, mes, venda_dia, meta_dia, meta_mes, peso_total, projecao_fechamento
  from painel_diario s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_dre_cascata with (security_barrier=true, security_invoker=false) as
  select mes, ano_mes, receita, cmv, impostos, margem_contribuicao, mc_perc, pessoal,
         infraestrutura, marketing, resultado_operacional, margem_op_perc, nao_operacional,
         contabil, capex, nao_categorizado, resultado_liquido, margem_liq_perc, cmv_perc,
         pessoal_perc
  from painel_dre_cascata s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_fluxo_caixa with (security_barrier=true, security_invoker=false) as
  select dia, tipo, saldo, saldo_real, saldo_projetado, entrada_projetada, saida_projetada,
         resultado_dia
  from painel_fluxo_caixa s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_margem_contribuicao with (security_barrier=true, security_invoker=false) as
  select mes, ano_mes, mc_perc
  from painel_margem_contribuicao s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_recebimento_canal with (security_barrier=true, security_invoker=false) as
  select ano_mes, canal, valor, qtd
  from painel_recebimento_canal s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_recebimento_hora with (security_barrier=true, security_invoker=false) as
  select ano_mes, hora, valor, qtd
  from painel_recebimento_hora s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_recebimento_resumo with (security_barrier=true, security_invoker=false) as
  select ano_mes, mes, recebido_total, qtd_transacoes, ticket_transacao
  from painel_recebimento_resumo s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_resumo_mensal with (security_barrier=true, security_invoker=false) as
  select mes, ano_mes, ano, faturamento, faturamento_proj, qtd_vendas, ticket_medio, meta,
         perc_meta, receita, despesa, resultado, cmv, pessoal, cmv_perc, pessoal_perc,
         margem_perc, saldo_fim, saldo_situacao
  from painel_resumo_mensal s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_saldo_atual with (security_barrier=true, security_invoker=false) as
  select data_ref, saldo_atual, data_comp, saldo_comp
  from painel_saldo_atual s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_saldo_fim_mes with (security_barrier=true, security_invoker=false) as
  select mes, ano_mes, saldo_fim, situacao
  from painel_saldo_fim_mes s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_saldo_por_conta with (security_barrier=true, security_invoker=false) as
  select conta, saldo, data_ref
  from painel_saldo_por_conta s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_painel_ultima_carga with (security_barrier=true, security_invoker=false) as
  select ultima
  from painel_ultima_carga s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_projecao_despesa_direta with (security_barrier=true, security_invoker=false) as
  select dia, valor
  from projecao_despesa_direta s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_projecao_despesa_fixa with (security_barrier=true, security_invoker=false) as
  select dia, valor
  from projecao_despesa_fixa s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_recebimento_conhecido with (security_barrier=true, security_invoker=false) as
  select dia, valor
  from recebimento_conhecido s
  where usuario_tem_papel(array['admin', 'socio']);

create or replace view public.app_recebimento_projetado with (security_barrier=true, security_invoker=false) as
  select dia, valor
  from recebimento_projetado s
  where usuario_tem_papel(array['admin', 'socio']);

commit;
