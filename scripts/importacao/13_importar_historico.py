#!/usr/bin/env python3
"""Carga única do histórico, mantida compatível e com validação prévia."""

import hashlib
import sys
from collections import Counter

from importacao_core import (
    Rejeicao,
    abrir_csv_validado,
    adicionar_rejeicao,
    campo,
    criar_parser,
    executar_com_saida,
    importar_registros,
    imprimir_resultado,
    ler_opcoes,
    parse_datetime_formatos,
    parse_inteiro,
    parse_valor_decimal,
    validar_leitura,
    valor_informado_invalido,
)


CABECALHOS = {
    "seq", "empresa", "movimentacao", "tipo", "valor", "saldo_antes",
    "saldo_depois", "tarifa", "data_iso", "situacao", "nosso_numero",
    "destino", "destino_documento", "destino_instituicao", "origem",
    "origem_documento", "origem_instituicao", "categoria", "dre_grupo",
    "fornecedor", "ajuste_manual", "detalhamento",
}
COLUNAS = [
    "seq", "empresa", "movimentacao", "tipo", "valor", "saldo_antes",
    "saldo_depois", "tarifa", "data_hora", "data_raw", "situacao",
    "nosso_numero", "destino", "destino_documento", "destino_instituicao",
    "origem", "origem_documento", "origem_instituicao", "categoria",
    "dre_grupo", "fornecedor", "ajuste_manual", "detalhamento", "dedup_hash",
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
            seq_raw = campo(row, "seq")
            data_raw = campo(row, "data_iso")
            valor_raw = campo(row, "valor")
            saldo_antes_raw = campo(row, "saldo_antes")
            saldo_depois_raw = campo(row, "saldo_depois")
            seq = parse_inteiro(seq_raw)
            data_hora = parse_datetime_formatos(
                data_raw, ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d")
            )
            valor = parse_valor_decimal(valor_raw)
            saldo_antes = parse_valor_decimal(saldo_antes_raw)
            saldo_depois = parse_valor_decimal(saldo_depois_raw)
            empresa = campo(row, "empresa")
            motivos = []
            if seq is None:
                motivos.append("sequência inválida")
            if not empresa:
                motivos.append("empresa ausente")
            if data_hora is None:
                motivos.append("data inválida")
            if valor is None:
                motivos.append("valor inválido")
            if valor_informado_invalido(saldo_antes_raw, saldo_antes):
                motivos.append("saldo antes inválido")
            if valor_informado_invalido(saldo_depois_raw, saldo_depois):
                motivos.append("saldo depois inválido")
            adicionar_rejeicao(rejeicoes, reader.line_num, motivos)
            if motivos:
                continue

            destino = campo(row, "destino")
            destino_documento = campo(row, "destino_documento")
            origem = campo(row, "origem")
            base = "|".join(
                [
                    seq_raw or "", empresa or "", data_raw or "", valor_raw or "",
                    destino or "", destino_documento or "", origem or "",
                ]
            )
            registros.append({
                "seq": seq,
                "empresa": empresa,
                "movimentacao": campo(row, "movimentacao"),
                "tipo": campo(row, "tipo"),
                "valor": valor,
                "saldo_antes": saldo_antes,
                "saldo_depois": saldo_depois,
                "tarifa": campo(row, "tarifa"),
                "data_hora": data_hora,
                "data_raw": data_raw,
                "situacao": campo(row, "situacao"),
                "nosso_numero": campo(row, "nosso_numero"),
                "destino": destino,
                "destino_documento": destino_documento,
                "destino_instituicao": campo(row, "destino_instituicao"),
                "origem": origem,
                "origem_documento": campo(row, "origem_documento"),
                "origem_instituicao": campo(row, "origem_instituicao"),
                "categoria": campo(row, "categoria"),
                "dre_grupo": campo(row, "dre_grupo"),
                "fornecedor": campo(row, "fornecedor"),
                "ajuste_manual": campo(row, "ajuste_manual"),
                "detalhamento": campo(row, "detalhamento"),
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
    hashes = {item["dedup_hash"] for item in registros}
    print("\n== Resumo do arquivo ==")
    print(f"  registros:           {len(registros)}")
    print(f"  hashes únicos:       {len(hashes)}")
    print(f"  duplicatas internas: {len(registros) - len(hashes)}")
    print(
        "  empresas:            "
        f"{dict(Counter(item['empresa'] for item in registros).most_common(6))}"
    )


def gravar(registros):
    return importar_registros(
        registros=registros,
        tabela="raw_historico",
        colunas=COLUNAS,
        conflito="(dedup_hash)",
        montar_linha=lambda item, _conta_id: [item[coluna] for coluna in COLUNAS],
        conta_nome=None,
        fonte_log=None,
        periodo=None,
        page_size=1000,
    )


def fluxo():
    opcoes = ler_opcoes(criar_parser("Importa a carga histórica única"))
    print(f"Lendo: {opcoes.arquivo}")
    registros, _periodo = ler_csv(opcoes.arquivo, opcoes)
    resumo(registros)
    if opcoes.dry_run:
        print("\n[DRY-RUN] Arquivo válido; nada foi gravado no banco.")
        return
    print("\n== Gravando histórico ==")
    imprimir_resultado(gravar(registros))
    print("\nOK.")


if __name__ == "__main__":
    sys.exit(executar_com_saida(fluxo))
