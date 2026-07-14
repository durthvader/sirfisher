-- O advisor de seguranca do Supabase acusou public.raw_bs_cash sem Row
-- Level Security. Na pratica a tabela ja e inacessivel a anon/authenticated
-- desde a criacao (20260725000000_importa_bs_cash.sql revoga todos os
-- privilegios desses papeis e concede acesso so a service_role, usado pelo
-- importador via DATABASE_URL, nunca via PostgREST). Habilitar RLS aqui e
-- so uma segunda camada de protecao: nao precisa de policy porque
-- service_role ignora RLS e nenhum outro papel tem grant na tabela.

begin;

alter table public.raw_bs_cash enable row level security;

commit;
