-- Correcao pontual de dado: os recolhimentos de 2026-06-29 e 2026-06-30
-- foram marcados pelo Rogerio durante a implantacao do controle de
-- responsaveis (sangria), mas quem de fato recolheu foi a Hemile Alexandre.
-- Ajusta apenas o vinculo de responsavel (recolhida_por), sem alterar
-- valores, datas ou o horario ja registrado em recolhida_em.

begin;

do $$
declare
  v_ids uuid[];
  v_hemile_id uuid;
  v_linhas int;
begin
  select array_agg(id) into v_ids
  from auth.users
  where raw_user_meta_data ->> 'full_name' ilike '%hemile%';

  if v_ids is null or array_length(v_ids, 1) <> 1 then
    raise exception using errcode = 'P0001',
      message = format('Esperado exatamente 1 usuario com nome contendo "hemile", encontrado: %s', coalesce(array_length(v_ids, 1), 0));
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
