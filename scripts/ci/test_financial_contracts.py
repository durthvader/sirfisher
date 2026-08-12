#!/usr/bin/env python3
"""Contratos estáticos das proteções financeiras e do Calendário."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "supabase" / "migrations"


def fail(message: str) -> None:
    raise AssertionError(message)


def require(text: str, fragments: tuple[str, ...], context: str) -> None:
    missing = [fragment for fragment in fragments if fragment not in text]
    if missing:
        fail(f"{context}; ausentes={missing}")


def main() -> int:
    continuity = (MIGRATIONS / "20260814000000_calendario_encadeia_saldo_entre_meses.sql").read_text(
        encoding="utf-8-sig"
    )
    require(
        continuity,
        (
            "least(p_mes, coalesce(ct.caixa, p_mes) + 1)",
            "where s.dia >= p_mes and s.dia < p_mes + interval '1 month'",
        ),
        "Calendário perdeu o encadeamento de saldo entre meses",
    )

    configured_sources = (
        MIGRATIONS / "20260818100000_calendario_usa_fontes_caixa.sql"
    ).read_text(encoding="utf-8-sig")
    require(
        configured_sources,
        (
            "public.listar_calendario_financeiro(date)",
            "public.listar_despesas_dia(date)",
            "cfg_fonte.ativa",
            "cfg_fonte.entra_caixa",
            "cfg_historica.entra_caixa_historico",
        ),
        "Calendário perdeu o filtro pelas fontes configuradas",
    )

    derived = (
        MIGRATIONS / "20260818110000_sincroniza_derivados_e_virada_diaria.sql"
    ).read_text(encoding="utf-8-sig")
    require(
        derived,
        (
            "private.validar_despesas_materializadas()",
            "private.validar_fluxo_materializado()",
            "private.validar_saldo_diario_materializado()",
            "refresh materialized view concurrently public.mv_despesa_mensal",
            "refresh materialized view concurrently public.mv_despesa_diaria",
            "refresh materialized view concurrently public.mv_saldo_caixa_diario_detalhado",
            "refresh materialized view concurrently public.mv_conciliacao_contabil",
            "sirfisher-virada-financeira",
            "select public.refresh_painel();",
        ),
        "Sincronização dos derivados perdeu uma proteção obrigatória",
    )

    generic_balance = (
        MIGRATIONS / "20260818120000_saldo_generico_por_conta.sql"
    ).read_text(encoding="utf-8-sig")
    require(
        generic_balance,
        (
            "private.movimento_saldo_conta",
            "private.mv_saldo_conta_diario",
            "private.saldo_caixa_diario",
            "Novo saldo por conta divergiu do snapshot anterior",
            "Nova âncora de saldo divergiu do valor anterior",
            "public.listar_saldo_contas_dia",
            "public.admin_salvar_conta_com_saldo",
            "public.admin_salvar_fonte_financeira_com_saldo",
            "refresh materialized view concurrently private.mv_saldo_conta_diario",
            "select public.refresh_painel();",
        ),
        "Saldo genérico perdeu uma proteção obrigatória",
    )

    latest_refresh = generic_balance.split(
        "create or replace function public.refresh_painel()", 1
    )[1].split("$function$;", 1)[0]
    if "refresh materialized view concurrently public.mv_saldo_caixa_diario_detalhado" in latest_refresh:
        fail("Refresh atual voltou a recalcular o snapshot fixo legado")

    calendar_html = (ROOT / "calendario.html").read_text(encoding="utf-8-sig")
    require(
        calendar_html,
        (
            "sb.rpc('listar_saldo_contas_dia'",
            "contasVisiveis.map",
            "formada pelas contas ativas configuradas",
        ),
        "Calendário perdeu o detalhamento dinâmico de contas",
    )
    if "sb.rpc('detalhar_saldo_caixa_dia'" in calendar_html:
        fail("Calendário voltou ao detalhamento fixo por banco")

    parameters_html = (ROOT / "parametros.html").read_text(encoding="utf-8-sig")
    editor_html = (ROOT / "parametros_editor.html").read_text(encoding="utf-8-sig")
    require(
        editor_html,
        (
            "saveRpc:'admin_salvar_conta_com_saldo'",
            "saveRpc:'admin_salvar_fonte_financeira_com_saldo'",
            "key:'saldo_metodo'",
            "key:'saldo_adaptador'",
        ),
        "Editor perdeu parâmetros do saldo por conta",
    )
    if "parametros_editor.html?t=saldo_inicial" in parameters_html:
        fail("Parâmetros voltou a exibir o cadastro duplicado de saldo inicial")

    configured_deposit = (
        MIGRATIONS / "20260818140000_conferencia_deposito_usa_conta_configurada.sql"
    ).read_text(encoding="utf-8-sig")
    require(
        configured_deposit,
        (
            "private.extrato_bancario_configuravel",
            "'bb:' || b.id::text",
            "'inter:' || i.id::text",
            "'bs_cash:' || c.id::text",
            "'stone_extrato:' || e.id::text",
            "A conta de deposito configurada mudaria os lancamentos conciliados",
            "e.conta_id = cfg.conta_deposito_id",
        ),
        "Conferência de depósito voltou a depender de uma conta fixa",
    )
    latest_deposit_detail = configured_deposit.split(
        "create or replace view public.app_conferencia_deposito_especie", 1
    )[1]
    if "from public.raw_bb" in latest_deposit_detail:
        fail("Conferência de depósito atual ainda consulta raw_bb diretamente")

    operational_alerts = (
        MIGRATIONS / "20260818150000_parametriza_alertas_operacionais.sql"
    ).read_text(encoding="utf-8-sig")
    require(
        operational_alerts,
        (
            "carga_dias_em_dia",
            "carga_dias_atencao",
            "sangria_dias_recentes",
            "conta_recorrente_alerta_dias",
            "private.validar_limites_status_carga",
            "'inter', 'Extrato Inter'",
            "'fundopay', 'Vendas Fundopay'",
            "join public.fonte_financeira f on f.chave = b.chave and f.ativa",
            "current_timestamp at time zone c.fuso_horario",
        ),
        "Alertas operacionais voltaram a depender de fontes ou prazos fixos",
    )

    print("FINANCIAL_CONTRACTS_OK calendar=2 derived=5 rollover=1 generic_balance=1 deposit_account=1 operational_alerts=1")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"FINANCIAL_CONTRACTS_ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
