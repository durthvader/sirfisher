#!/usr/bin/env python3
"""Contratos estáticos mínimos para autenticação e autorização das páginas."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AUTH = ROOT / "assets" / "auth.js"
MIGRATIONS = ROOT / "supabase" / "migrations"


def fail(message: str) -> None:
    raise AssertionError(message)


def latest_function(migrations: str, function_name: str) -> str:
    markers = list(
        re.finditer(
            rf"create\s+or\s+replace\s+function\s+public\.{function_name}\s*\(",
            migrations,
            re.I,
        )
    )
    if not markers:
        fail(f"RPC {function_name} não encontrada nas migrations")
    start = markers[-1].start()
    next_function = re.search(
        r"\ncreate\s+or\s+replace\s+function\s+", migrations[start + 1 :], re.I
    )
    end = start + 1 + next_function.start() if next_function else len(migrations)
    return migrations[start:end]


def main() -> int:
    pages = {path.name for path in ROOT.glob("*.html")}
    auth = AUTH.read_text(encoding="utf-8")
    configured = set(re.findall(r"'([a-z0-9_]+\.html)'", auth))

    missing = sorted(pages - configured)
    extra = sorted(configured - pages)
    if missing or extra:
        fail(f"Matriz de acesso divergente; ausentes={missing}; extras={extra}")

    unprotected = []
    raw_access = []
    for page in sorted(ROOT.glob("*.html")):
        html = page.read_text(encoding="utf-8")
        if "SirFisherAuth.requireRole" not in html:
            unprotected.append(page.name)
        if re.search(r"\.from\(['\"]raw_", html):
            raw_access.append(page.name)

    if unprotected:
        fail("Páginas sem gate de autenticação: " + ", ".join(unprotected))
    if raw_access:
        fail("Páginas consultam tabelas raw diretamente: " + ", ".join(raw_access))

    dashboard = (ROOT / "index.html").read_text(encoding="utf-8")
    if "const r=await sb.from('app_painel_resumo_mensal')" not in dashboard:
        fail("Index precisa liberar o resumo antes das consultas secundárias")
    if dashboard.count("Promise.allSettled([") < 2 or "function applyResult(" not in dashboard:
        fail("Index perdeu o carregamento progressivo tolerante a falhas")
    if "DETAIL_OK.dre" not in dashboard or "DETAIL_OK.fixa" not in dashboard or "DETAIL_OK.direta" not in dashboard:
        fail("Index pode exibir resultado tendencial com projeção incompleta")

    migrations = "\n".join(
        path.read_text(encoding="utf-8-sig")
        for path in sorted(MIGRATIONS.glob("*.sql"))
    )
    for function_name in ("listar_contas_recorrentes", "salvar_conta_recorrente"):
        definition = latest_function(migrations, function_name)
        if "public.usuario_pode_acessar_pagina('contas_recorrentes.html')" not in definition:
            fail(f"RPC {function_name} perdeu a permissão configurável da página")

    parametro = latest_function(migrations, "parametro_valor")
    if not re.search(r"security\s+definer", parametro, re.I):
        fail("parametro_valor precisa executar sem SELECT direto em parametros")
    if "set search_path = pg_catalog, pg_temp" not in parametro:
        fail("parametro_valor perdeu o search_path seguro")
    if "from public.parametros" not in parametro:
        fail("parametro_valor perdeu a referência qualificada ao catálogo")
    if not re.search(
        r"revoke\s+all\s+privileges\s+on\s+table\s+public\.parametros\s+"
        r"from\s+public,\s*anon,\s*authenticated",
        parametro,
        re.I,
    ):
        fail("parametros precisa continuar sem leitura direta pela Data API")
    if re.search(
        r"grant\s+execute\s+on\s+function\s+public\.parametro_valor"
        r"\s*\(text,\s*numeric\)\s+to\s+[^;]*\banon\b",
        parametro,
        re.I,
    ):
        fail("anon não deve executar parametro_valor diretamente")

    empresa = latest_function(migrations, "app_configuracao_empresa")
    if not re.search(r"security\s+invoker", empresa, re.I):
        fail("app_configuracao_empresa precisa respeitar RLS")
    if re.search(r"\bwhere\s+[^;]*\bsingleton\b", empresa, re.I | re.S):
        fail("app_configuracao_empresa não pode exigir SELECT na coluna singleton")
    if not re.search(r"\blimit\s+1\b", empresa, re.I):
        fail("app_configuracao_empresa perdeu o contrato singleton")

    print(f"ACCESS_CONTRACTS_OK pages={len(pages)} roles=admin,socio,gerente")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"ACCESS_CONTRACTS_ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
