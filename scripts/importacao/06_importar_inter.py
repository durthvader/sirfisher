#!/usr/bin/env python3
"""Importa o extrato da conta Inter (encerrada) com validação prévia.

O export da Inter usa ponto e vírgula, traz um preâmbulo antes do
cabeçalho real e pode ter codificação mista (linhas UTF-8 e latin-1 no
mesmo arquivo, quando editado manualmente), por isso a leitura decodifica
linha a linha em vez de usar abrir_csv_validado.
"""

import csv
import hashlib
import io
import sys
from collections import Counter

from importacao_core import (
    Rejeicao,
    ValidacaoErro,
    adicionar_rejeicao,
    atualizar_painel,
    campo,
    criar_parser,
    executar_com_saida,
    importar_registros,
    imprimir_resultado,
    ler_opcoes,
    parse_data_formatos,
    parse_valor_brasileiro,
    validar_arquivo,
    validar_leitura,
)


CABECALHOS = {"Data Lançamento", "Histórico", "Descrição", "Valor", "Saldo"}
COLUNAS = [
    "conta_id", "data", "data_raw", "historico", "descricao",
    "valor", "saldo", "dedup_hash",
]


def _decodificar_linhas(caminho):
    linhas = []
    for bruto in caminho.read_bytes().splitlines():
        try:
            linhas.append(bruto.decode("utf-8"))
        except UnicodeDecodeError:
            linhas.append(bruto.decode("latin-1"))
    return linhas


def _reader_apos_preambulo(linhas):
    for indice, linha in enumerate(linhas):
        campos = next(csv.reader([linha], delimiter=";"), [])
        if campos and campos[0].strip() == "Data Lançamento":
            cabecalhos = [c.strip() for c in campos]
            ausentes = sorted(CABECALHOS - set(cabecalhos))
            if ausentes:
                raise ValidacaoErro(
                    "cabeçalhos obrigatórios ausentes: " + ", ".join(ausentes)
                )
            corpo = "\n".join(linhas[indice:])
            return csv.DictReader(io.StringIO(corpo), delimiter=";"), indice
    raise ValidacaoErro("cabeçalho 'Data Lançamento' não encontrado no arquivo")


def ler_csv(caminho, opcoes):
    arquivo = validar_arquivo(caminho)
    linhas = _decodificar_linhas(arquivo)
    reader, linha_base = _reader_apos_preambulo(linhas)

    registros = []
    rejeicoes: list[Rejeicao] = []
    ignoradas = 0
    total = 0
    for numero, row in enumerate(reader, start=linha_base + 2):
        data_raw = campo(row, "Data Lançamento")
        if not data_raw and not campo(row, "Valor"):
            ignoradas += 1
            continue
        total += 1

        valor_raw = campo(row, "Valor")
        saldo_raw = campo(row, "Saldo")
        data = parse_data_formatos(data_raw, ("%d/%m/%Y",))
        valor = parse_valor_brasileiro(valor_raw)
        saldo = parse_valor_brasileiro(saldo_raw)
        historico = campo(row, "Histórico")
        motivos = []
        if data is None:
            motivos.append("data inválida")
        if valor is None:
            motivos.append("valor inválido")
        if not historico:
            motivos.append("histórico ausente")
        adicionar_rejeicao(rejeicoes, numero, motivos)
        if motivos:
            continue

        descricao = campo(row, "Descrição")
        base = f"{data_raw}|{historico}|{descricao}|{valor_raw}|{saldo_raw}"
        registros.append({
            "data": data,
            "data_raw": data_raw,
            "historico": historico,
            "descricao": descricao,
            "valor": valor,
            "saldo": saldo,
            "dedup_hash": hashlib.md5(base.encode("utf-8")).hexdigest(),
        })

    periodo = validar_leitura(
        registros=registros,
        total_linhas=total,
        rejeicoes=rejeicoes,
        datas=(item["data"] for item in registros),
        opcoes=opcoes,
        ignoradas=ignoradas,
    )
    return registros, ignoradas, periodo


def resumo(registros, ignoradas):
    hashes = {item["dedup_hash"] for item in registros}
    creditos = sum(item["valor"] for item in registros if item["valor"] > 0)
    debitos = sum(item["valor"] for item in registros if item["valor"] < 0)
    print("\n== Resumo do arquivo ==")
    print(f"  transações:          {len(registros)}")
    print(f"  linhas ignoradas:    {ignoradas}")
    print(f"  hashes únicos:       {len(hashes)}")
    print(f"  duplicatas internas: {len(registros) - len(hashes)}")
    print(f"  créditos:            {creditos:,.2f}")
    print(f"  débitos:             {debitos:,.2f}")
    print(
        "  históricos:          "
        f"{dict(Counter(item['historico'] for item in registros).most_common(8))}"
    )


def gravar(registros, periodo):
    return importar_registros(
        registros=registros,
        tabela="raw_inter",
        colunas=COLUNAS,
        conflito="(dedup_hash)",
        montar_linha=lambda item, conta_id: (
            [conta_id] + [item[coluna] for coluna in COLUNAS[1:]]
        ),
        fonte_log="Extrato Inter",
        periodo=periodo,
        fonte_chave="inter",
    )


def fluxo():
    opcoes = ler_opcoes(criar_parser("Importa o extrato da conta Inter"))
    print(f"Lendo: {opcoes.arquivo}")
    registros, ignoradas, periodo = ler_csv(opcoes.arquivo, opcoes)
    resumo(registros, ignoradas)
    if opcoes.dry_run:
        print("\n[DRY-RUN] Arquivo válido; nada foi gravado no banco.")
        return
    print("\n== Gravando, recalculando e registrando carga ==")
    imprimir_resultado(gravar(registros, periodo))
    print("\n== Atualizando painel ==")
    atualizar_painel()
    print("  painel atualizado.")
    print("\nOK.")


if __name__ == "__main__":
    sys.exit(executar_com_saida(fluxo))
