#!/usr/bin/env python3
"""Importa o extrato Stone com validação integral antes da transação."""

import hashlib
import sys
from collections import Counter

from importacao_core import (
    Rejeicao,
    abrir_csv_validado,
    adicionar_rejeicao,
    atualizar_painel,
    campo,
    criar_parser,
    executar_com_saida,
    importar_registros,
    imprimir_resultado,
    ler_opcoes,
    parse_datetime_formatos,
    parse_valor_brasileiro,
    validar_leitura,
    valor_informado_invalido,
)


FORMATOS_DATA = ("%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y")
CABECALHOS = {
    "Movimentação", "Tipo", "Valor", "Saldo antes", "Saldo depois",
    "Tarifa", "Data", "Horário", "Situação", "Nosso Número", "Destino",
    "Destino Documento", "Destino Instituição", "Destino Agência",
    "Destino Conta", "Origem", "Origem Documento", "Origem Instituição",
    "Origem Agência", "Origem Conta", "Descrição",
}
COLUNAS = [
    "conta_id", "movimentacao", "tipo", "valor", "saldo_antes",
    "saldo_depois", "tarifa", "data_hora", "data_hora_raw", "horario",
    "situacao", "nosso_numero", "destino", "destino_documento",
    "destino_instituicao", "destino_agencia", "destino_conta", "origem",
    "origem_documento", "origem_instituicao", "origem_agencia",
    "origem_conta", "descricao", "origem_carga", "dedup_hash",
]


def ler_csv(caminho, opcoes):
    registros = []
    rejeicoes: list[Rejeicao] = []
    total = 0
    with abrir_csv_validado(
        caminho,
        encoding="utf-8-sig",
        delimiter=",",
        cabecalhos_obrigatorios=CABECALHOS,
    ) as reader:
        for row in reader:
            total += 1
            data_raw = campo(row, "Data")
            valor_raw = campo(row, "Valor")
            saldo_antes_raw = campo(row, "Saldo antes")
            saldo_depois_raw = campo(row, "Saldo depois")
            data_hora = parse_datetime_formatos(data_raw, FORMATOS_DATA)
            valor = parse_valor_brasileiro(valor_raw)
            saldo_antes = parse_valor_brasileiro(saldo_antes_raw)
            saldo_depois = parse_valor_brasileiro(saldo_depois_raw)
            movimentacao = campo(row, "Movimentação")
            motivos = []
            if data_hora is None:
                motivos.append("data inválida")
            if valor is None:
                motivos.append("valor inválido")
            if not movimentacao:
                motivos.append("movimentação ausente")
            if valor_informado_invalido(saldo_antes_raw, saldo_antes):
                motivos.append("saldo antes inválido")
            if valor_informado_invalido(saldo_depois_raw, saldo_depois):
                motivos.append("saldo depois inválido")
            adicionar_rejeicao(rejeicoes, reader.line_num, motivos)
            if motivos:
                continue

            horario = campo(row, "Horário")
            destino_documento = campo(row, "Destino Documento")
            base = f"{data_raw}|{horario}|{valor_raw}|{saldo_depois_raw}|{destino_documento}"
            registros.append({
                "movimentacao": movimentacao,
                "tipo": campo(row, "Tipo"),
                "valor": valor,
                "saldo_antes": saldo_antes,
                "saldo_depois": saldo_depois,
                "tarifa": campo(row, "Tarifa"),
                "data_hora": data_hora,
                "data_hora_raw": data_raw,
                "horario": horario,
                "situacao": campo(row, "Situação"),
                "nosso_numero": campo(row, "Nosso Número"),
                "destino": campo(row, "Destino"),
                "destino_documento": destino_documento,
                "destino_instituicao": campo(row, "Destino Instituição"),
                "destino_agencia": campo(row, "Destino Agência"),
                "destino_conta": campo(row, "Destino Conta"),
                "origem": campo(row, "Origem"),
                "origem_documento": campo(row, "Origem Documento"),
                "origem_instituicao": campo(row, "Origem Instituição"),
                "origem_agencia": campo(row, "Origem Agência"),
                "origem_conta": campo(row, "Origem Conta"),
                "descricao": campo(row, "Descrição"),
                "dedup_hash": hashlib.md5(base.encode("utf-8")).hexdigest(),
            })

    periodo = validar_leitura(
        registros=registros,
        total_linhas=total,
        rejeicoes=rejeicoes,
        datas=(item["data_hora"] for item in registros),
        opcoes=opcoes,
    )
    return registros, periodo


def resumo(registros):
    movimentacoes = Counter(item["movimentacao"] for item in registros)
    hashes = {item["dedup_hash"] for item in registros}
    print("\n== Resumo do arquivo ==")
    print(f"  registros:           {len(registros)}")
    print(f"  movimentação:        {dict(movimentacoes)}")
    print(f"  hashes únicos:       {len(hashes)}")
    print(f"  duplicatas internas: {len(registros) - len(hashes)}")


def gravar(registros, periodo):
    return importar_registros(
        registros=registros,
        tabela="raw_stone_extrato",
        colunas=COLUNAS,
        conflito="(dedup_hash)",
        montar_linha=lambda item, conta_id: (
            [conta_id]
            + [item[coluna] for coluna in COLUNAS[1:-2]]
            + ["stone_extrato", item["dedup_hash"]]
        ),
        conta_nome="Stone",
        fonte_log="Extrato Stone",
        periodo=periodo,
    )


def fluxo():
    opcoes = ler_opcoes(criar_parser("Importa o extrato Stone"))
    print(f"Lendo: {opcoes.arquivo}")
    registros, periodo = ler_csv(opcoes.arquivo, opcoes)
    resumo(registros)
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
