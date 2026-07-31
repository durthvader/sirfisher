-- Fecha a unica tabela public identificada sem RLS.
--
-- stone_estabelecimento e uma tabela interna de mapeamento usada por views e
-- funcoes security definer. O navegador nao precisa consulta-la diretamente.
-- Sem policies, RLS nega por padrao o acesso comum; o owner continua podendo
-- usa-la na composicao das views e RPCs existentes.
--
-- Risco: baixo. Os privilegios de anon e authenticated ja estavam revogados;
-- esta migration acrescenta a protecao estrutural e revoga tambem PUBLIC.

begin;

alter table public.stone_estabelecimento enable row level security;

revoke all privileges on table public.stone_estabelecimento
  from public, anon, authenticated;

commit;
