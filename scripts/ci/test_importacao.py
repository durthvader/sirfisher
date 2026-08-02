#!/usr/bin/env python3
"""Dry-runs sintéticos dos importadores, sem banco e sem dados reais."""

from __future__ import annotations

import csv
import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
IMPORT_DIR = ROOT / "scripts" / "importacao"
sys.path.insert(0, str(IMPORT_DIR))

CASES = [
    ("01_importar_extrato_stone.py", ",", "utf-8-sig", [{"Movimentação": "Crédito", "Valor": "10,00", "Saldo antes": "0,00", "Saldo depois": "10,00", "Data": "01/07/2026 10:00"}]),
    ("02_importar_vendas_stone.py", ";", "utf-8-sig", [{"DATA DA VENDA": "01/07/2026 10:00", "STONE ID": "teste-1", "VALOR BRUTO": "10,00", "VALOR LIQUIDO": "9,50"}]),
    ("03_importar_recebiveis_stone.py", ";", "utf-8-sig", [{"DATA DA VENDA": "01/07/2026 10:00", "DATA DE VENCIMENTO": "02/07/2026", "DATA DE VENCIMENTO ORIGINAL": "02/07/2026", "STONE ID": "teste-1", "QTD DE PARCELAS": "1", "Nº DA PARCELA": "1", "VALOR BRUTO": "10,00", "VALOR LÍQUIDO": "9,50"}]),
    ("04_importar_bb.py", ",", "latin-1", [
        {"Data": "01/07/2026", "Lançamento": "Saldo Anterior", "Valor": "100,00"},
        {"Data": "01/07/2026", "Lançamento": "Pix recebido", "Valor": "10,00"},
        {"Data": "01/07/2026", "Lançamento": "S A L D O", "Valor": "110,00"},
    ]),
    ("13_importar_historico.py", ",", "utf-8-sig", [{"seq": "1", "empresa": "Stone", "valor": "10.00", "saldo_antes": "0.00", "saldo_depois": "10.00", "data_iso": "2026-07-01 10:00:00"}]),
]


def load_module(path: Path, index: int):
    spec = importlib.util.spec_from_file_location(f"import_test_{index}", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


def write_csv(path: Path, module, delimiter: str, encoding: str, values_list) -> None:
    headers = sorted(module.CABECALHOS)
    with path.open("w", encoding=encoding, newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers, delimiter=delimiter)
        writer.writeheader()
        for values in values_list:
            row = {key: "" for key in headers}
            row.update(values)
            writer.writerow(row)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        for index, (script, delimiter, encoding, values_list) in enumerate(CASES):
            module = load_module(IMPORT_DIR / script, index)
            csv_path = tmp_path / f"case-{index}.csv"
            write_csv(csv_path, module, delimiter, encoding, values_list)
            result = subprocess.run(
                [sys.executable, str(IMPORT_DIR / script), str(csv_path), "--dry-run"],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                raise AssertionError(f"{script} retornou {result.returncode}: {result.stdout}")

        invalid = tmp_path / "invalid.csv"
        invalid.write_text("coluna_errada\nvalor\n", encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(IMPORT_DIR / "02_importar_vendas_stone.py"), str(invalid), "--dry-run"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 2:
            raise AssertionError(f"CSV inválido deveria retornar 2, retornou {result.returncode}")

        bb_module = load_module(IMPORT_DIR / "04_importar_bb.py", len(CASES))
        invalid_balance = tmp_path / "invalid-bb-balance.csv"
        write_csv(invalid_balance, bb_module, ",", "latin-1", [
            {"Data": "01/07/2026", "Lançamento": "Saldo Anterior", "Valor": "100,00"},
            {"Data": "01/07/2026", "Lançamento": "Pix recebido", "Valor": "10,00"},
            {"Data": "01/07/2026", "Lançamento": "S A L D O", "Valor": "108,00"},
        ])
        result = subprocess.run(
            [sys.executable, str(IMPORT_DIR / "04_importar_bb.py"), str(invalid_balance), "--dry-run"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 2 or "saldo final não confere" not in result.stdout:
            raise AssertionError(
                "Saldo BB divergente deveria ser rejeitado com a mensagem de reconciliação"
            )

    print(f"IMPORT_TESTS_OK dry_runs={len(CASES)} invalid_header=1 invalid_bb_balance=1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
