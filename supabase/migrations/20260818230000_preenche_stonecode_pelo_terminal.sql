-- =====================================================================
-- Preenche o stonecode ausente pelo terminal e faz a linha nascer completa
-- =====================================================================
--
-- MOTIVO
--   9.994 vendas da Stone estão sem `stonecode`: vieram de importações
--   antigas, quando o campo ainda não era gravado. Isso obriga qualquer
--   regra sobre código de origem a carregar uma exceção -- "código presente
--   e desconhecido fica de fora, sem código continua entrando" -- e regra
--   com exceção é regra que alguém aplica errado depois.
--
--   Preenchendo o histórico, a regra futura fica sem exceção: código
--   ausente ou não cadastrado fica de fora do faturamento.
--
-- EVIDÊNCIA (medida antes de escrever esta migration)
--   - as 9.994 linhas sem código têm número de série: 9.994 (100%);
--   - séries conhecidas no cadastro: 23, e nenhuma delas ambígua -- nenhum
--     terminal pertenceu a mais de um estabelecimento;
--   - linhas resolvíveis pela série: 9.994 (100%);
--   - código resultante: um só, 770398216 (Praia, unidade do painel);
--   - recebíveis sem código: zero, já estão todos preenchidos.
--
--   O preenchimento é determinístico, não é atribuição por semelhança.
--
-- POR QUE NENHUM NÚMERO MUDA
--   `recebimento_stone_net`, única view que lê `stonecode`, já resolve a
--   série em tempo de leitura: `COALESCE(v.stonecode, m.stonecode)` sobre o
--   mesmo mapa terminal -> código. Gravar o valor faz o COALESCE escolher
--   exatamente o que ele já escolhia. As linhas também já estão na conta 1
--   (Stone/Praia), então `conta_id` não se move.
--
-- OBJETOS
--   + private.stonecode_preenchido           (auditoria, torna reversível)
--   ~ public.raw_stone_vendas.stonecode      (preenchimento onde era nulo)
--   ~ private.definir_conta_stone()          (grava o código resolvido)
--
-- SOBRE O GATILHO
--   Ele já resolvia a conta pela série; agora grava também o código, para o
--   buraco não voltar a se formar. Duas coisas que ele NÃO faz, de
--   propósito:
--   - não sobrescreve código presente, mesmo desconhecido. Esse código é a
--     evidência de que apareceu estabelecimento novo, e é o que a quarentena
--     do próximo passo vai usar;
--   - não inventa código quando a série é nova. Aí a linha fica sem código
--     mesmo, e cai na mesma regra de "não cadastrado".
--
-- RISCO: baixo, e a migration prova o resultado.
--   - Só preenche onde `stonecode` é nulo e a série resolve para um único
--     código; série ambígua é ignorada pelo `having count(distinct) = 1`.
--   - O faturamento por mês é medido antes e depois: qualquer diferença
--     aborta a transação inteira.
--   - Reversível: `private.stonecode_preenchido` guarda os ids afetados.
--     Para desfazer, basta anular o `stonecode` desses ids.
-- =====================================================================

begin;

create table if not exists private.stonecode_preenchido (
  raw_id bigint primary key,
  tabela text not null,
  stonecode text not null,
  n_serie text,
  preenchido_em timestamptz not null default now()
);

comment on table private.stonecode_preenchido is
  'Vendas Stone que tiveram o stonecode deduzido do terminal em 20260818230000. Guarda os ids para tornar o preenchimento reversível.';

revoke all privileges on table private.stonecode_preenchido from public, anon, authenticated;

-- Faturamento antes, para provar que o preenchimento é inerte.
create temporary table faturamento_antes on commit drop as
select date_trunc('month', r.data_venda)::date as mes,
       round(sum(r.bruto_net), 2) as bruto,
       count(*) as linhas
from public.recebimento_stone_net r
group by 1;

create temporary table conta_antes on commit drop as
select conta_id, count(*) as linhas
from public.raw_stone_vendas
group by 1;

-- Só série inequívoca entra no mapa. Se um terminal algum dia aparecer com
-- dois estabelecimentos, ele fica de fora em vez de ser chutado.
create temporary table mapa_terminal on commit drop as
select nullif(v.n_serie, '') as n_serie, min(v.stonecode) as stonecode
from public.raw_stone_vendas v
where v.stonecode is not null and nullif(v.n_serie, '') is not null
group by 1
having count(distinct v.stonecode) = 1;

insert into private.stonecode_preenchido (raw_id, tabela, stonecode, n_serie)
select v.id, 'raw_stone_vendas', m.stonecode, v.n_serie
from public.raw_stone_vendas v
join mapa_terminal m on m.n_serie = nullif(v.n_serie, '')
where v.stonecode is null
on conflict (raw_id) do nothing;

update public.raw_stone_vendas v
   set stonecode = m.stonecode
  from mapa_terminal m
 where m.n_serie = nullif(v.n_serie, '')
   and v.stonecode is null;

-- O gatilho passa a gravar o código resolvido, não só a conta.
create or replace function private.definir_conta_stone()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, pg_temp
as $function$
declare
  v_conta smallint;
  v_codigo text;
  v_serie text := nullif(to_jsonb(new) ->> 'n_serie', '');
begin
  if new.stonecode is not null then
    select s.conta_id into v_conta
    from public.stone_conta s
    where s.stonecode = new.stonecode and s.ativa;
  end if;

  if v_conta is null and tg_table_name = 'raw_stone_vendas' and v_serie is not null then
    select v.stonecode, s.conta_id into v_codigo, v_conta
    from public.raw_stone_vendas v
    join public.stone_conta s on s.stonecode = v.stonecode and s.ativa
    where v.n_serie = v_serie and v.stonecode is not null
    order by v.id desc
    limit 1;

    -- Preenche apenas quando o arquivo não trouxe código nenhum. Código
    -- presente e desconhecido fica como veio: sobrescrever apagaria a
    -- evidência de que apareceu um estabelecimento novo.
    if new.stonecode is null and v_codigo is not null then
      new.stonecode := v_codigo;
    end if;
  end if;

  new.conta_id := coalesce(v_conta, new.conta_id);
  return new;
end;
$function$;

comment on function private.definir_conta_stone() is
  'Resolve conta e código de origem da venda Stone. Sem código no arquivo, deduz ambos pelo terminal e grava o código; código presente é preservado como veio, mesmo desconhecido.';

-- Prova numérica.
do $validacao$
declare
  v_preenchidas integer;
  v_restantes integer;
  v_divergencia record;
begin
  select count(*) into v_preenchidas from private.stonecode_preenchido;

  select count(*) into v_restantes
  from public.raw_stone_vendas v
  join mapa_terminal m on m.n_serie = nullif(v.n_serie, '')
  where v.stonecode is null;

  if v_restantes > 0 then
    raise exception
      'Sobraram % vendas sem stonecode com série conhecida.', v_restantes;
  end if;

  for v_divergencia in
    select a.mes, a.bruto as antes,
           coalesce(d.bruto, 0) as depois,
           a.linhas as linhas_antes, coalesce(d.linhas, 0) as linhas_depois
    from faturamento_antes a
    full join (
      select date_trunc('month', r.data_venda)::date as mes,
             round(sum(r.bruto_net), 2) as bruto,
             count(*) as linhas
      from public.recebimento_stone_net r
      group by 1
    ) d on d.mes = a.mes
    where a.bruto is distinct from d.bruto
       or a.linhas is distinct from d.linhas
  loop
    raise exception
      'Faturamento de % mudou: antes % (% linhas), depois % (% linhas).',
      to_char(v_divergencia.mes, 'YYYY-MM'), v_divergencia.antes,
      v_divergencia.linhas_antes, v_divergencia.depois,
      v_divergencia.linhas_depois;
  end loop;

  -- `full join` exige condição merge/hash-joinable, então `is not distinct
  -- from` não serve aqui. Normaliza o nulo para um sentinela e compara por
  -- igualdade, o que preserva a intenção (conta sem id conta como um grupo).
  if exists (
    select 1
    from (
      select coalesce(a.conta_id, -1) as conta_id, a.linhas from conta_antes a
    ) a
    full join (
      select coalesce(conta_id, -1) as conta_id, count(*) as linhas
      from public.raw_stone_vendas group by 1
    ) d on d.conta_id = a.conta_id
    where a.linhas is distinct from d.linhas
  ) then
    raise exception 'A distribuição de vendas por conta mudou.';
  end if;

  if position('new.stonecode := v_codigo' in
              pg_get_functiondef('private.definir_conta_stone'::regproc)) = 0 then
    raise exception 'O gatilho não passou a gravar o código resolvido.';
  end if;

  raise notice 'stonecode preenchido em % vendas, faturamento inalterado.', v_preenchidas;
end;
$validacao$;

commit;
