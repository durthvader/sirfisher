-- =====================================================================
-- Edicao admin das demais tabelas de parametros (via RPCs SECURITY DEFINER)
-- =====================================================================
--
-- Segue o padrao de 20260720000000 (parametros): as tabelas de config ficam
-- trancadas para o navegador; a edicao passa por RPCs SECURITY DEFINER com
-- gate de admin. Nao mexemos em RLS/policies/grants das tabelas (varias tem
-- policies load-bearing para views de projecao).
--
-- Tabelas: recebimento_regra, peso_dia_semana, grupo_variavel, saldo_inicial,
--          meta_mensal, conta, unidade. Para cada uma: admin_listar_X() e
--          admin_salvar_X(...). Sem DELETE (conta/unidade usam a flag ativa).
--
-- RISCO: baixo. So adiciona funcoes restritas a admin; nao altera tabelas
--        nem views. Saves fazem UPDATE (edicao) ou UPSERT/INSERT controlado.
-- =====================================================================

begin;

-- Guard compartilhado.
create or replace function public.exigir_admin()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if not public.usuario_tem_papel(array['admin']::text[]) then
    raise exception using errcode = '42501', message = 'Apenas administradores.';
  end if;
end;
$$;
revoke all privileges on function public.exigir_admin() from public, anon, authenticated;

-- ---- recebimento_regra (PK forma) : edita percentual/dias/taxa ----
create or replace function public.admin_listar_recebimento_regra()
returns setof public.recebimento_regra language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
begin perform public.exigir_admin();
  return query select * from public.recebimento_regra order by forma; end; $$;

create or replace function public.admin_salvar_recebimento_regra(
  p_forma text, p_percentual numeric, p_dias integer, p_taxa numeric)
returns public.recebimento_regra language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare v public.recebimento_regra;
begin perform public.exigir_admin();
  update public.recebimento_regra
    set percentual = p_percentual, dias = p_dias, taxa = p_taxa
    where forma = p_forma returning * into v;
  if not found then raise exception using errcode='22023', message='Forma desconhecida: '||coalesce(p_forma,'(nulo)'); end if;
  return v; end; $$;

-- ---- peso_dia_semana (PK dow) : edita peso ----
create or replace function public.admin_listar_peso_dia_semana()
returns setof public.peso_dia_semana language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
begin perform public.exigir_admin();
  return query select * from public.peso_dia_semana order by dow; end; $$;

create or replace function public.admin_salvar_peso_dia_semana(p_dow integer, p_peso numeric)
returns public.peso_dia_semana language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare v public.peso_dia_semana;
begin perform public.exigir_admin();
  update public.peso_dia_semana set peso = p_peso where dow = p_dow returning * into v;
  if not found then raise exception using errcode='22023', message='Dia desconhecido.'; end if;
  return v; end; $$;

-- ---- grupo_variavel (PK grupo) : edita flag variavel ----
create or replace function public.admin_listar_grupo_variavel()
returns setof public.grupo_variavel language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
begin perform public.exigir_admin();
  return query select * from public.grupo_variavel order by grupo; end; $$;

create or replace function public.admin_salvar_grupo_variavel(p_grupo text, p_variavel boolean)
returns public.grupo_variavel language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare v public.grupo_variavel;
begin perform public.exigir_admin();
  update public.grupo_variavel set variavel = coalesce(p_variavel,false) where grupo = p_grupo returning * into v;
  if not found then raise exception using errcode='22023', message='Grupo desconhecido: '||coalesce(p_grupo,'(nulo)'); end if;
  return v; end; $$;

-- ---- saldo_inicial (PK conta) : edita/adiciona (upsert por conta) ----
create or replace function public.admin_listar_saldo_inicial()
returns setof public.saldo_inicial language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
begin perform public.exigir_admin();
  return query select * from public.saldo_inicial order by conta; end; $$;

create or replace function public.admin_salvar_saldo_inicial(
  p_conta text, p_data_base date, p_saldo numeric, p_obs text)
returns public.saldo_inicial language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare v public.saldo_inicial;
begin perform public.exigir_admin();
  if coalesce(p_conta,'') = '' then raise exception using errcode='22023', message='Conta obrigatoria.'; end if;
  insert into public.saldo_inicial(conta, data_base, saldo, obs)
    values (p_conta, p_data_base, p_saldo, p_obs)
  on conflict (conta) do update
    set data_base = excluded.data_base, saldo = excluded.saldo, obs = excluded.obs
  returning * into v;
  return v; end; $$;

-- ---- meta_mensal (PK mes,unidade) : edita/adiciona ----
create or replace function public.admin_listar_meta_mensal()
returns setof public.meta_mensal language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
begin perform public.exigir_admin();
  return query select * from public.meta_mensal order by mes desc, unidade; end; $$;

create or replace function public.admin_salvar_meta_mensal(
  p_mes date, p_unidade text, p_meta_bruta numeric)
returns public.meta_mensal language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare v public.meta_mensal; v_mes date; v_uni text;
begin perform public.exigir_admin();
  if p_mes is null then raise exception using errcode='22023', message='Mes obrigatorio.'; end if;
  v_mes := date_trunc('month', p_mes)::date;
  v_uni := nullif(trim(coalesce(p_unidade,'')), '');
  if v_uni is null then raise exception using errcode='22023', message='Unidade obrigatoria.'; end if;
  insert into public.meta_mensal(mes, unidade, meta_bruta)
    values (v_mes, v_uni, p_meta_bruta)
  on conflict (mes, unidade) do update set meta_bruta = excluded.meta_bruta
  returning * into v;
  return v; end; $$;

-- ---- conta (PK id identity) : edita/adiciona (id nulo = insere) ----
create or replace function public.admin_listar_conta()
returns setof public.conta language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
begin perform public.exigir_admin();
  return query select * from public.conta order by id; end; $$;

create or replace function public.admin_salvar_conta(
  p_id smallint, p_nome text, p_banco text, p_unidade_id smallint, p_ativa boolean)
returns public.conta language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare v public.conta;
begin perform public.exigir_admin();
  if coalesce(trim(coalesce(p_nome,'')),'') = '' then raise exception using errcode='22023', message='Nome obrigatorio.'; end if;
  if p_id is null then
    insert into public.conta(nome, banco, unidade_id, ativa)
      values (p_nome, p_banco, p_unidade_id, coalesce(p_ativa,true)) returning * into v;
  else
    update public.conta set nome=p_nome, banco=p_banco, unidade_id=p_unidade_id, ativa=coalesce(p_ativa,true)
      where id = p_id returning * into v;
    if not found then raise exception using errcode='22023', message='Conta id desconhecido.'; end if;
  end if;
  return v; end; $$;

-- ---- unidade (PK id identity) : edita/adiciona ----
create or replace function public.admin_listar_unidade()
returns setof public.unidade language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
begin perform public.exigir_admin();
  return query select * from public.unidade order by id; end; $$;

create or replace function public.admin_salvar_unidade(
  p_id smallint, p_nome text, p_ativa boolean)
returns public.unidade language plpgsql security definer
set search_path = pg_catalog, pg_temp as $$
declare v public.unidade;
begin perform public.exigir_admin();
  if coalesce(trim(coalesce(p_nome,'')),'') = '' then raise exception using errcode='22023', message='Nome obrigatorio.'; end if;
  if p_id is null then
    insert into public.unidade(nome, ativa) values (p_nome, coalesce(p_ativa,true)) returning * into v;
  else
    update public.unidade set nome=p_nome, ativa=coalesce(p_ativa,true) where id = p_id returning * into v;
    if not found then raise exception using errcode='22023', message='Unidade id desconhecido.'; end if;
  end if;
  return v; end; $$;

-- Exposicao: so authenticated (o gate interno restringe a admin).
do $$
declare fn text;
begin
  foreach fn in array array[
    'public.admin_listar_recebimento_regra()',
    'public.admin_salvar_recebimento_regra(text,numeric,integer,numeric)',
    'public.admin_listar_peso_dia_semana()',
    'public.admin_salvar_peso_dia_semana(integer,numeric)',
    'public.admin_listar_grupo_variavel()',
    'public.admin_salvar_grupo_variavel(text,boolean)',
    'public.admin_listar_saldo_inicial()',
    'public.admin_salvar_saldo_inicial(text,date,numeric,text)',
    'public.admin_listar_meta_mensal()',
    'public.admin_salvar_meta_mensal(date,text,numeric)',
    'public.admin_listar_conta()',
    'public.admin_salvar_conta(smallint,text,text,smallint,boolean)',
    'public.admin_listar_unidade()',
    'public.admin_salvar_unidade(smallint,text,boolean)'
  ]
  loop
    execute format('revoke all privileges on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end;
$$;

commit;
