#!/usr/bin/env python3
"""Contratos estáticos mínimos para autenticação e autorização das páginas."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AUTH = ROOT / "assets" / "auth.js"


def fail(message: str) -> None:
    raise AssertionError(message)


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

    print(f"ACCESS_CONTRACTS_OK pages={len(pages)} roles=admin,socio,gerente")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"ACCESS_CONTRACTS_ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
