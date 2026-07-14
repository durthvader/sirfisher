#!/usr/bin/env python3
"""Detecta o tipo de CSV pelo cabeçalho e roteia para o importador correto.

Cada origem (extrato Stone, vendas Stone, recebíveis Stone, BB, BS Cash)
continua com seu módulo próprio, contendo a lógica de parsing e validação
específica. Este dispatcher só decide qual módulo usar, comparando o
cabeçalho do CSV recebido com o conjunto ``CABECALHOS`` de cada um, antes de
abrir qualquer conexão com o banco.

Para adicionar uma nova origem no futuro: criar o módulo seguindo o mesmo
padrão dos existentes (constantes ``CABECALHOS``/``COLUNAS`` e funções
``ler_csv``/``resumo``/``gravar``) e incluí-lo em ``REGISTRO`` abaixo.
"""

from __future__ import annotations

import csv
import importlib
import sys
from pathlib import Path
from types import ModuleType

from importacao_core import (
    OpcoesImportacao,
    ValidacaoErro,
    atualizar_painel,
    criar_parser,
    executar_com_saida,
    imprimir_resultado,
    ler_opcoes,
    validar_arquivo,
)


REGISTRO = [
    ("01_importar_extrato_stone", "utf-8-sig", ","),
    ("02_importar_vendas_stone", "utf-8-sig", ";"),
    ("03_importar_recebiveis_stone", "utf-8-sig", ";"),
    ("04_importar_bb", "latin-1", ","),
    ("05_importar_bs_cash", "utf-8", ","),
]


def _ler_cabecalho(caminho: Path, encoding: str, delimiter: str) -> list[str]:
    try:
        with caminho.open(encoding=encoding, newline="") as handle:
            return next(csv.reader(handle, delimiter=delimiter), [])
    except (UnicodeError, OSError):
        return []


def detectar_modulo(caminho: Path) -> ModuleType:
    candidatos: list[ModuleType] = []
    for nome, encoding, delimiter in REGISTRO:
        modulo = importlib.import_module(nome)
        cabecalho = set(_ler_cabecalho(caminho, encoding, delimiter))
        if modulo.CABECALHOS <= cabecalho:
            candidatos.append(modulo)

    if not candidatos:
        raise ValidacaoErro("nenhum importador reconhece o cabeçalho deste CSV")
    if len(candidatos) > 1:
        nomes = ", ".join(m.__name__ for m in candidatos)
        raise ValidacaoErro(
            f"cabeçalho ambíguo, reconhecido por mais de um importador: {nomes}"
        )
    return candidatos[0]


def _ler_e_resumir(modulo: ModuleType, caminho: Path, opcoes: OpcoesImportacao):
    resultado = modulo.ler_csv(caminho, opcoes)
    if len(resultado) == 3:
        registros, ignoradas, periodo = resultado
        modulo.resumo(registros, ignoradas)
    else:
        registros, periodo = resultado
        modulo.resumo(registros)
    return registros, periodo


def fluxo() -> None:
    opcoes = ler_opcoes(
        criar_parser(
            "Detecta o tipo do CSV e importa "
            "(extrato/vendas/recebíveis Stone, BB ou BS Cash)"
        )
    )
    caminho = validar_arquivo(opcoes.arquivo)
    modulo = detectar_modulo(caminho)
    print(f"Lendo: {caminho}")
    print(f"Tipo detectado: {modulo.__name__}")

    registros, periodo = _ler_e_resumir(modulo, caminho, opcoes)

    if opcoes.dry_run:
        print("\n[DRY-RUN] Arquivo válido; nada foi gravado no banco.")
        return

    print("\n== Gravando, recalculando e registrando carga ==")
    imprimir_resultado(modulo.gravar(registros, periodo))
    print("\n== Atualizando painel ==")
    atualizar_painel()
    print("  painel atualizado.")
    print("\nOK.")


if __name__ == "__main__":
    sys.exit(executar_com_saida(fluxo))
