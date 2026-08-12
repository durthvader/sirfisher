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

    print("FINANCIAL_CONTRACTS_OK calendar=2 derived=5 rollover=1")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"FINANCIAL_CONTRACTS_ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
