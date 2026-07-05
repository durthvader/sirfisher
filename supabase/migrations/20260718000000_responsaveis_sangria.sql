-- Responsaveis pelas etapas operacionais da sangria.
-- Registros anteriores permanecem com responsavel nulo porque nao e seguro
-- inferir quem executou uma acao passada.

begin;

alter table public.venda_especie
  add column if not exists cadastrado_por uuid references auth.users(id) on delete set null,
  add column if not exists recolhida_por uuid references auth.users(id) on delete set null,
  add column if not exists depositada_por uuid references auth.users(id) on delete set null;

comment on column public.venda_especie.cadastrado_por is
  'Usuario que registrou originalmente o valor da sangria.';
comment on column public.venda_especie.recolhida_por is
  'Usuario que marcou a sangria como recolhida.';
comment on column public.venda_especie.depositada_por is
  'Usuario que marcou a sangria como depositada.';

-- Fecha o ciclo dos registros que ja existiam antes desta implantacao. Como
-- nao ha historico confiavel de usuario ou momento, preservamos os responsaveis
-- nulos e usamos a propria data da sangria apenas como referencia de data.
update public.venda_especie
   set recolhida_em = coalesce(
         recolhida_em,
         data::timestamp at time zone 'America/Fortaleza'
       ),
       depositada_em = coalesce(
         depositada_em,
         data::timestamp at time zone 'America/Fortaleza'
       )
 where recolhida_em is null
    or depositada_em is null;

create or replace function public.salvar_sangria(
  p_data date,
  p_unidade text,
  p_valor numeric
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_id bigint;
  v_usuario uuid := auth.uid();
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;
  if p_data is null or p_valor is null or p_valor < 0 then
    raise exception using errcode = '22023', message = 'Data ou valor invalido.';
  end if;

  insert into public.venda_especie (data, unidade, valor, cadastrado_por)
  values (p_data, coalesce(nullif(p_unidade, ''), 'PRAIA'), p_valor, v_usuario)
  on conflict (data, unidade) do update
    set valor = excluded.valor,
        cadastrado_por = venda_especie.cadastrado_por
  returning id::bigint into v_id;

  return v_id;
end;
$function$;

create or replace function public.alterar_status_sangria(
  p_id bigint,
  p_acao text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_recolhida_em timestamptz;
  v_depositada_em timestamptz;
  v_usuario uuid := auth.uid();
begin
  if not public.usuario_tem_papel(array['admin', 'socio', 'gerente']) then
    raise exception using errcode = '42501', message = 'Acesso nao autorizado.';
  end if;

  select v.recolhida_em, v.depositada_em
    into v_recolhida_em, v_depositada_em
  from public.venda_especie v
  where v.id = p_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Sangria nao encontrada.';
  end if;

  case p_acao
    when 'recolher' then
      if v_recolhida_em is null then
        update public.venda_especie
           set recolhida_em = now(), recolhida_por = v_usuario
         where id = p_id;
      end if;
    when 'desfazer_recolhimento' then
      if v_depositada_em is not null then
        raise exception using errcode = '22023', message = 'Desfaca o deposito antes do recolhimento.';
      end if;
      update public.venda_especie
         set recolhida_em = null, recolhida_por = null
       where id = p_id;
    when 'depositar' then
      if v_recolhida_em is null then
        raise exception using errcode = '22023', message = 'Marque a sangria como recolhida antes do deposito.';
      end if;
      if v_depositada_em is null then
        update public.venda_especie
           set depositada_em = now(), depositada_por = v_usuario
         where id = p_id;
      end if;
    when 'desfazer_deposito' then
      update public.venda_especie
         set depositada_em = null, depositada_por = null
       where id = p_id;
    else
      raise exception using errcode = '22023', message = 'Acao de sangria invalida.';
  end case;
end;
$function$;

create or replace view public.app_venda_especie_controle
with (security_barrier = true, security_invoker = false) as
select
  v.id,
  v.data,
  v.unidade,
  v.valor,
  v.observacao,
  v.criado_em,
  v.recolhida_em,
  v.depositada_em,
  coalesce(uc.raw_user_meta_data ->> 'full_name', uc.raw_user_meta_data ->> 'name')::text as cadastrado_por_nome,
  coalesce(ur.raw_user_meta_data ->> 'full_name', ur.raw_user_meta_data ->> 'name')::text as recolhida_por_nome,
  coalesce(ud.raw_user_meta_data ->> 'full_name', ud.raw_user_meta_data ->> 'name')::text as depositada_por_nome
from public.venda_especie v
left join auth.users uc on uc.id = v.cadastrado_por
left join auth.users ur on ur.id = v.recolhida_por
left join auth.users ud on ud.id = v.depositada_por
where public.usuario_tem_papel(array['admin', 'socio', 'gerente']);

revoke insert, update on table public.venda_especie from authenticated;
revoke all privileges on function public.salvar_sangria(date, text, numeric) from public, anon;
revoke all privileges on function public.alterar_status_sangria(bigint, text) from public, anon;
grant execute on function public.salvar_sangria(date, text, numeric) to authenticated;
grant execute on function public.alterar_status_sangria(bigint, text) to authenticated;
revoke all privileges on public.app_venda_especie_controle from public, anon;
grant select on public.app_venda_especie_controle to authenticated;

commit;
