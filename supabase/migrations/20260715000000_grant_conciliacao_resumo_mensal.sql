-- =====================================================================
-- Corrige grant faltante em app_conciliacao_stone_resumo_mensal
-- =====================================================================
--
-- A view foi criada na migration anterior (20260714000000) sem
-- conceder select para authenticated - erro de "permission denied"
-- reportado pelo usuario ao carregar conciliacao.html.
-- =====================================================================

begin;

revoke all privileges on table public.app_conciliacao_stone_resumo_mensal
from public, anon, authenticated;

grant select on table public.app_conciliacao_stone_resumo_mensal
to authenticated;

commit;
