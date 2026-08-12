-- Torna editáveis a janela histórica e a regra de recorrência de fornecedores.
-- Os defaults (6 meses, 60% e mínimo de 2 meses) reproduzem exatamente o
-- comportamento anterior do front-end; nenhum lançamento financeiro é alterado.

begin;

insert into public.parametros (chave, valor, descricao) values
  ('fornecedor_meses_historico', 6, 'Meses usados na comparação de fornecedores'),
  ('fornecedor_recorrencia_presenca_perc', 60, 'Presença mensal para considerar fornecedor recorrente'),
  ('fornecedor_recorrencia_min_meses', 2, 'Presença mínima, incluindo o mês atual, para considerar fornecedor recorrente')
on conflict (chave) do nothing;

update public.parametros
set grupo = 'Análise de fornecedores',
    unidade_medida = case
      when chave = 'fornecedor_recorrencia_presenca_perc' then 'percentual'
      else 'meses'
    end,
    valor_min = 1,
    valor_max = case
      when chave = 'fornecedor_recorrencia_presenca_perc' then 100
      else 24
    end,
    ordem = case chave
      when 'fornecedor_meses_historico' then 250
      when 'fornecedor_recorrencia_presenca_perc' then 260
      when 'fornecedor_recorrencia_min_meses' then 270
      else ordem
    end
where chave in (
  'fornecedor_meses_historico',
  'fornecedor_recorrencia_presenca_perc',
  'fornecedor_recorrencia_min_meses'
);

create or replace function private.validar_parametros_fornecedor()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, pg_temp
as $$
declare
  v_outro numeric;
begin
  if new.chave = 'fornecedor_meses_historico' then
    select p.valor into v_outro
    from public.parametros p
    where p.chave = 'fornecedor_recorrencia_min_meses';
    if v_outro is not null and new.valor + 1 < v_outro then
      raise exception using errcode = '22023',
        message = 'A janela histórica, somada ao mês atual, não pode ser menor que a presença mínima.';
    end if;
  elsif new.chave = 'fornecedor_recorrencia_min_meses' then
    select p.valor into v_outro
    from public.parametros p
    where p.chave = 'fornecedor_meses_historico';
    if v_outro is not null and new.valor > v_outro + 1 then
      raise exception using errcode = '22023',
        message = 'A presença mínima não pode superar a janela histórica somada ao mês atual.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_parametros_fornecedor on public.parametros;
create trigger trg_validar_parametros_fornecedor
before insert or update of valor on public.parametros
for each row
when (new.chave in (
  'fornecedor_meses_historico',
  'fornecedor_recorrencia_min_meses'
))
execute function private.validar_parametros_fornecedor();

revoke all privileges on function private.validar_parametros_fornecedor()
from public, anon, authenticated;

commit;
