#!/usr/bin/env python3
"""Verificações estruturais da cadeia de migrations, sem banco ou dados reais."""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS = ROOT / "supabase" / "migrations"
NAME = re.compile(r"^(?P<version>\d{14})_(?P<name>[a-z0-9_]+)\.sql$")


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> int:
    files = sorted(path for path in MIGRATIONS.glob("*.sql") if path.is_file())
    if not files:
        fail("Nenhuma migration encontrada")

    invalid = [path.name for path in files if not NAME.fullmatch(path.name)]
    if invalid:
        fail("Nome de migration inválido: " + ", ".join(invalid))

    versions = [NAME.fullmatch(path.name).group("version") for path in files]
    duplicates = sorted(version for version, count in Counter(versions).items() if count > 1)
    if duplicates:
        fail("Versões de migration duplicadas: " + ", ".join(duplicates))

    empty = [path.name for path in files if not path.read_text(encoding="utf-8-sig").strip()]
    if empty:
        fail("Migrations vazias: " + ", ".join(empty))

    if versions != sorted(versions):
        fail("A lista de migrations não está ordenada por versão")

    print(f"MIGRATION_TESTS_OK count={len(files)} first={versions[0]} last={versions[-1]}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"MIGRATION_TESTS_ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
