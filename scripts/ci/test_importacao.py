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

import importacao_core

CASES = [
    ("01_importar_extrato_stone.py", ",", "utf-8-sig", [{"Movimentação": "Crédito", "Valor": "10,00", "Saldo antes": "0,00", "Saldo depois": "10,00", "Data": "01/07/2026 10:00"}]),
    ("02_importar_vendas_stone.py", ";", "utf-8-sig", [{"DATA DA VENDA": "01/07/2026 10:00", "STONE ID": "teste-1", "VALOR BRUTO": "10,00", "VALOR LIQUIDO": "9,50"}]),
    ("03_importar_recebiveis_stone.py", ";", "utf-8-sig", [{"DATA DA VENDA": "01/07/2026 10:00", "DATA DE VENCIMENTO": "02/07/2026", "DATA DE VENCIMENTO ORIGINAL": "02/07/2026", "STONE ID": "teste-1", "QTD DE PARCELAS": "1", "Nº DA PARCELA": "1", "VALOR BRUTO": "10,00", "VALOR LÍQUIDO": "9,50"}]),
    # Formato antigo do BB: o débito vem com sinal e com sufixo "D".
    ("04_importar_bb.py", ",", "latin-1", [
        {"Data": "01/07/2026", "Lançamento": "Saldo Anterior", "Valor": "100,00 C"},
        {"Data": "01/07/2026", "Lançamento": "Pix recebido", "Valor": "10,00 C", "Tipo Lançamento": "Entrada"},
        {"Data": "01/07/2026", "Lançamento": "Pix - Enviado", "Valor": "-4,00 D", "Tipo Lançamento": "Saída"},
        {"Data": "01/07/2026", "Lançamento": "S A L D O", "Valor": "106,00 C"},
    ]),
    # Formato de agosto/2026: o débito perdeu o sinal e o "Tipo Lançamento"
    # diz "Entrada" mesmo na saída. Só o sufixo "D" identifica o débito.
    ("04_importar_bb.py", ",", "latin-1", [
        {"Data": "01/08/2026", "Lançamento": "Saldo Anterior", "Valor": "100,00 C"},
        {"Data": "01/08/2026", "Lançamento": "Pix recebido", "Valor": "10,00 C", "Tipo Lançamento": "Entrada"},
        {"Data": "01/08/2026", "Lançamento": "Pix - Enviado", "Valor": "4,00 D", "Tipo Lançamento": "Entrada"},
        {"Data": "01/08/2026", "Lançamento": "S A L D O", "Valor": "106,00 C"},
    ]),
    ("05_importar_bs_cash.py", ",", "utf-8", [{
        "Data": "01/07/2026 10:00:00", "Dcto.": "1", "Operação": "PIX",
        "Histórico": "Crédito", "Favorecido": "Teste", "Créditos (R$)": "10,00",
        "Saldo (R$)": "10,00",
    }]),
    ("07_importar_fundopay.py", ";", "utf-8-sig", [{
        "ID Venda": "teste-1", "Data Venda": "01/07/2026 10:00:00",
        "Valor Venda": "10,00", "Valor Liquido": "9,50", "Situacao": "Aprovada",
        "Parcelas": "1",
    }]),
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


def run_dry_run(script: str, csv_path: Path) -> None:
    result = subprocess.run(
        [sys.executable, str(IMPORT_DIR / script), str(csv_path), "--dry-run"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(f"{script} retornou {result.returncode}: {result.stdout}")


def write_inter_fixture(path: Path) -> None:
    path.write_text(
        "Extrato da conta\n"
        "Data Lançamento;Histórico;Descrição;Valor;Saldo\n"
        "01/07/2026;Pix recebido;Teste;10,00;10,00\n",
        encoding="utf-8",
    )


class CursorFonteFake:
    def __init__(self, retorno):
        self.retorno = retorno
        self.consulta = None
        self.parametros = None

    def execute(self, consulta, parametros):
        self.consulta = consulta
        self.parametros = parametros

    def fetchone(self):
        return self.retorno


def test_resolucao_conta_fonte() -> None:
    conta = importacao_core._resolver_conta_fonte(
        CursorFonteFake((None,)),
        "fundopay",
        conta_obrigatoria=False,
    )
    if conta is not None:
        raise AssertionError("Fonte de vendas sem conta deveria ser aceita")

    try:
        importacao_core._resolver_conta_fonte(
            CursorFonteFake((None,)),
            "stone_extrato",
            conta_obrigatoria=True,
        )
    except importacao_core.ErroOperacional as exc:
        if "sem conta configurada" not in str(exc):
            raise AssertionError("Erro de conta obrigatória ficou ambíguo") from exc
    else:
        raise AssertionError("Fonte financeira sem conta deveria ser rejeitada")

    try:
        importacao_core._resolver_conta_fonte(
            CursorFonteFake(None),
            "fonte_inativa",
            conta_obrigatoria=False,
        )
    except importacao_core.ErroOperacional as exc:
        if "inexistente ou inativa" not in str(exc):
            raise AssertionError("Erro de fonte inativa ficou ambíguo") from exc
    else:
        raise AssertionError("Fonte inexistente ou inativa deveria ser rejeitada")


def test_valor_e_hash_bb(bb_module) -> None:
    if bb_module.parse_valor_bb("1.234,56 D") != -1234.56:
        raise AssertionError("Débito sem sinal deveria virar negativo pelo sufixo D")
    if bb_module.parse_valor_bb("-1.234,56 D") != -1234.56:
        raise AssertionError("Débito no formato antigo deveria continuar negativo")
    if bb_module.parse_valor_bb("1.234,56 C") != 1234.56:
        raise AssertionError("Crédito deveria ficar positivo")
    if bb_module.parse_valor_bb("") is not None:
        raise AssertionError("Valor vazio deveria continuar inválido")

    # O mesmo lançamento reexportado no formato novo tem de cair no mesmo
    # dedup_hash, senão a reimportação duplica o histórico.
    linhas = [
        {"Data": "01/08/2026", "Lançamento": "Saldo Anterior", "Valor": "100,00 C"},
        {"Data": "01/08/2026", "Lançamento": "Pix - Enviado", "Valor": "SINAL", "N° documento": "9"},
        {"Data": "01/08/2026", "Lançamento": "S A L D O", "Valor": "96,00 C"},
    ]
    hashes = []
    with tempfile.TemporaryDirectory() as tmp:
        for valor in ("-4,00 D", "4,00 D"):
            caminho = Path(tmp) / f"bb-{len(hashes)}.csv"
            atual = [dict(linha) for linha in linhas]
            atual[1]["Valor"] = valor
            write_csv(caminho, bb_module, ",", "latin-1", atual)
            opcoes = bb_module.ler_opcoes(
                bb_module.criar_parser("teste"), [str(caminho), "--dry-run"]
            )
            registros, _, _ = bb_module.ler_csv(caminho, opcoes)
            hashes.append([item["dedup_hash"] for item in registros])
    if hashes[0] != hashes[1]:
        raise AssertionError("Formatos antigo e novo do BB geraram dedup_hash diferentes")


def main() -> int:
    test_resolucao_conta_fonte()
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        for index, (script, delimiter, encoding, values_list) in enumerate(CASES):
            module = load_module(IMPORT_DIR / script, index)
            csv_path = tmp_path / f"case-{index}.csv"
            write_csv(csv_path, module, delimiter, encoding, values_list)
            run_dry_run(script, csv_path)

        inter_path = tmp_path / "inter.csv"
        write_inter_fixture(inter_path)
        run_dry_run("06_importar_inter.py", inter_path)

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
        test_valor_e_hash_bb(bb_module)
        invalid_balance = tmp_path / "invalid-bb-balance.csv"
        write_csv(invalid_balance, bb_module, ",", "latin-1", [
            {"Data": "01/07/2026", "Lançamento": "Saldo Anterior", "Valor": "100,00 C"},
            {"Data": "01/07/2026", "Lançamento": "Pix recebido", "Valor": "10,00 C"},
            {"Data": "01/07/2026", "Lançamento": "S A L D O", "Valor": "108,00 C"},
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

    print(
        f"IMPORT_TESTS_OK dry_runs={len(CASES) + 1} invalid_header=1 "
        "invalid_bb_balance=1 source_account_rules=3 bb_formatos=2"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
