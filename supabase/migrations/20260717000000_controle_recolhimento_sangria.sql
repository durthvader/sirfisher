-- Controle operacional da sangria em especie.
-- Os marcadores nao geram lancamento financeiro: registram somente quando o
-- dinheiro saiu do quiosque e quando foi depositado no banco.

begin;

alter table public.venda_especie
  add column if not exists recolhida_em timestamptz,
  add column if not exists depositada_em timestamptz;

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'venda_especie_deposito_exige_recolhimento'
      and conrelid = 'public.venda_especie'::regclass
  ) then
    alter table public.venda_especie
      add constraint venda_especie_deposito_exige_recolhimento
      check (depositada_em is null or recolhida_em is not null);
  end if;
end;
$migration$;

comment on column public.venda_especie.recolhida_em is
  'Momento em que a sangria foi retirada do quiosque.';
comment on column public.venda_especie.depositada_em is
  'Momento em que a sangria recolhida foi depositada no banco.';

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
        update public.venda_especie set recolhida_em = now() where id = p_id;
      end if;
    when 'desfazer_recolhimento' then
      if v_depositada_em is not null then
        raise exception using errcode = '22023', message = 'Desfaca o deposito antes do recolhimento.';
      end if;
      update public.venda_especie set recolhida_em = null where id = p_id;
    when 'depositar' then
      if v_recolhida_em is null then
        raise exception using errcode = '22023', message = 'Marque a sangria como recolhida antes do deposito.';
      end if;
      if v_depositada_em is null then
        update public.venda_especie set depositada_em = now() where id = p_id;
      end if;
    when 'desfazer_deposito' then
      update public.venda_especie set depositada_em = null where id = p_id;
    else
      raise exception using errcode = '22023', message = 'Acao de sangria invalida.';
  end case;
end;
$function$;

revoke all privileges on function public.alterar_status_sangria(bigint, text) from public, anon;
grant execute on function public.alterar_status_sangria(bigint, text) to authenticated;

commit;
