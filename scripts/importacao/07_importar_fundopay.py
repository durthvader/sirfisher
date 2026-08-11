#!/usr/bin/env python3
"""Importa a lista de vendas da Fundopay (maquininha paralela à Stone).

O export usa ponto e vírgula, BOM UTF-8 e traz todas as situações
(Aprovada, Negada, Desfeita). Todas são gravadas; o filtro para o
faturamento vive em `venda_diaria`, que só considera as aprovadas.
"""

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
    parse_inteiro,
    parse_valor_brasileiro,
    validar_leitura,
)


CABECALHOS = {
    "ID Venda", "Data Venda", "Bandeira", "Parcelas", "Modalidade",
    "Valor Venda", "Mdr", "Antecipacao", "Valor Liquido", "Tipo Terminal",
    "Terminal", "Data Confirmação Venda", "Situacao",
}
COLUNAS = [
    "id_venda", "data_venda", "bandeira", "n_parcelas", "modalidade",
    "valor_venda", "mdr", "antecipacao", "valor_liquido", "tipo_terminal",
    "terminal", "data_confirmacao", "situacao", "dedup_hash",
]
FORMATOS_DATA = ("%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y")


def ler_csv(caminho, opcoes):
    registros = []
    rejeicoes: list[Rejeicao] = []
    total = 0
    with abrir_csv_validado(
        caminho,
        encoding="utf-8-sig",
        delimiter=";",
        cabecalhos_obrigatorios=CABECALHOS,
    ) as reader:
        for row in reader:
            total += 1
            id_venda = campo(row, "ID Venda")
            data_raw = campo(row, "Data Venda")
            valor_raw = campo(row, "Valor Venda")
            situacao = campo(row, "Situacao")

            data_venda = parse_datetime_formatos(data_raw, FORMATOS_DATA)
            valor_venda = parse_valor_brasileiro(valor_raw)
            motivos = []
            if not id_venda:
                motivos.append("ID Venda ausente")
            if data_venda is None:
                motivos.append("data de venda inválida")
            if valor_venda is None:
                motivos.append("valor de venda inválido")
            if not situacao:
                motivos.append("situação ausente")
            adicionar_rejeicao(rejeicoes, reader.line_num, motivos)
            if motivos:
                continue

            registros.append({
                "id_venda": id_venda,
                "data_venda": data_venda,
                "bandeira": campo(row, "Bandeira"),
                "n_parcelas": parse_inteiro(campo(row, "Parcelas")),
                "modalidade": campo(row, "Modalidade"),
                "valor_venda": valor_venda,
                "mdr": parse_valor_brasileiro(campo(row, "Mdr")),
                "antecipacao": parse_valor_brasileiro(campo(row, "Antecipacao")),
                "valor_liquido": parse_valor_brasileiro(campo(row, "Valor Liquido")),
                "tipo_terminal": campo(row, "Tipo Terminal"),
                "terminal": campo(row, "Terminal"),
                "data_confirmacao": parse_datetime_formatos(
                    campo(row, "Data Confirmação Venda"), FORMATOS_DATA
                ),
                "situacao": situacao,
                # ID Venda é único no export; o hash mantém o padrão das
                # demais cargas e protege contra reexport com ajuste.
                "dedup_hash": hashlib.md5(id_venda.encode("utf-8")).hexdigest(),
            })

    periodo = validar_leitura(
        registros=registros,
        total_linhas=total,
        rejeicoes=rejeicoes,
        datas=(item["data_venda"] for item in registros),
        opcoes=opcoes,
    )
    return registros, periodo


def resumo(registros):
    hashes = {item["dedup_hash"] for item in registros}
    situacoes = Counter(item["situacao"] for item in registros)
    aprovadas = [
        item for item in registros
        if (item["situacao"] or "").strip().lower() == "aprovada"
    ]
    bruto = sum(item["valor_venda"] for item in aprovadas)
    print("\n== Resumo do arquivo ==")
    print(f"  registros:           {len(registros)}")
    print(f"  hashes únicos:       {len(hashes)}")
    print(f"  duplicatas internas: {len(registros) - len(hashes)}")
    print(f"  situações:           {dict(situacoes)}")
    print(f"  aprovadas:           {len(aprovadas)}")
    print(f"  faturamento bruto:   {bruto:,.2f}  (só aprovadas)")
    print(
        "  modalidades:         "
        f"{dict(Counter(item['modalidade'] for item in aprovadas))}"
    )
    print("  (Negada/Desfeita são gravadas mas ficam fora do faturamento)")


def gravar(registros, periodo):
    return importar_registros(
        registros=registros,
        tabela="raw_fundopay_vendas",
        colunas=COLUNAS,
        conflito="(dedup_hash)",
        montar_linha=lambda item, _conta_id: [item[coluna] for coluna in COLUNAS],
        fonte_log="Vendas Fundopay",
        periodo=periodo,
        fonte_chave="fundopay",
    )


def fluxo():
    opcoes = ler_opcoes(criar_parser("Importa a lista de vendas da Fundopay"))
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
