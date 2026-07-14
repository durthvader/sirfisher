-- A migration 20260741000000 tentou reatribuir os recolhimentos de
-- 2026-06-29 e 2026-06-30 (venda_especie, unidade PRAIA) para a Hemile
-- Alexandre, mas o filtro ilike '%hemile%' (sem acento) nao bateu com o
-- nome cadastrado ("HEMILE ALEXANDRE" com E acentuado), o que fez a
-- transacao abortar e nao teve efeito nenhum. Esta migration refaz a
-- correcao usando o nome exato ja confirmado em auth.users.

begin;

do $$
declare
  v_ids uuid[];
  v_hemile_id uuid;
  v_linhas int;
begin
  select array_agg(id) into v_ids
  from auth.users
  where raw_user_meta_data ->> 'full_name' = 'HÊMILE ALEXANDRE';

  if v_ids is null or array_length(v_ids, 1) <> 1 then
    raise exception using errcode = 'P0001',
      message = format('Esperado exatamente 1 usuario com full_name = HEMILE ALEXANDRE, encontrado: %s', coalesce(array_length(v_ids, 1), 0));
  end if;

  v_hemile_id := v_ids[1];

  update public.venda_especie
     set recolhida_por = v_hemile_id
   where unidade = 'PRAIA'
     and data in ('2026-06-29', '2026-06-30');

  get diagnostics v_linhas = row_count;
  raise notice 'Recolhimentos reatribuidos a Hemile: %', v_linhas;
end $$;

commit;
