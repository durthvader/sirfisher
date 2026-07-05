#!/usr/bin/env python3
"""Importa extrato da conta BS Cash com validação antes da transação.

O CSV traz Créditos e Débitos em colunas separadas (não um valor único com
sinal, como no BB) e data+hora completas. Todo o arquivo é gravado em
raw_bs_cash, mas fato_financeiro só passa a considerar lançamentos a partir
de CORTE_FATO_FINANCEIRO — ver migration 20260725000000_importa_bs_cash
para o motivo (evitar duplicar o que raw_historico já conta entre 2023 e
2025).
"""

import hashlib
import sys
from datetime import date

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
)


CABECALHOS = {
    "Data", "Dcto.", "Operação", "Histórico", "Favorecido",
    "Créditos (R$)", "Débitos (R$)", "Saldo (R$)",
}
COLUNAS = [
    "conta_id", "data_hora", "data_raw", "dcto", "operacao", "historico",
    "favorecido", "valor", "saldo", "dedup_hash",
]
FORMATOS_DATA = ("%d/%m/%Y %H:%M:%S", "%d/%m/%Y")

# Mesmo corte usado para stone_extrato/bb em fato_financeiro (só cosmético
# aqui: informa o usuário quantos registros deste arquivo vão "valer" nos
# painéis; quem decide de fato é a view).
CORTE_FATO_FINANCEIRO = date(2026, 1, 1)


def ler_csv(caminho, opcoes):
    registros = []
    rejeicoes: list[Rejeicao] = []
    ignoradas = 0
    total = 0
    with abrir_csv_validado(
        caminho,
        encoding="utf-8",
        delimiter=",",
        cabecalhos_obrigatorios=CABECALHOS,
    ) as reader:
        for row in reader:
            total += 1
            data_raw = campo(row, "Data")
            if data_raw is None:
                # Linhas de saldo (ex.: "SALDO ANTERIOR") não têm Data.
                ignoradas += 1
                continue

            data_hora = parse_datetime_formatos(data_raw, FORMATOS_DATA)
            creditos_raw = campo(row, "Créditos (R$)")
            debitos_raw = campo(row, "Débitos (R$)")
            valor_raw = creditos_raw or debitos_raw
            valor = parse_valor_brasileiro(valor_raw)
            saldo = parse_valor_brasileiro(campo(row, "Saldo (R$)"))

            motivos = []
            if data_hora is None:
                motivos.append("data inválida")
            if valor is None:
                motivos.append("valor inválido (sem crédito nem débito)")
            adicionar_rejeicao(rejeicoes, reader.line_num, motivos)
            if motivos:
                continue

            dcto = campo(row, "Dcto.")
            operacao = campo(row, "Operação")
            historico = campo(row, "Histórico")
            favorecido = campo(row, "Favorecido")
            base = f"{data_raw}|{dcto}|{operacao}|{valor_raw}|{favorecido}"
            registros.append({
                "data_hora": data_hora,
                "data_raw": data_raw,
                "dcto": dcto,
                "operacao": operacao,
                "historico": historico,
                "favorecido": favorecido,
                "valor": valor,
                "saldo": saldo,
                "dedup_hash": hashlib.md5(base.encode("utf-8")).hexdigest(),
            })

    periodo = validar_leitura(
        registros=registros,
        total_linhas=total,
        rejeicoes=rejeicoes,
        datas=(item["data_hora"] for item in registros),
        opcoes=opcoes,
        ignoradas=ignoradas,
    )
    return registros, ignoradas, periodo


def resumo(registros, ignoradas):
    hashes = {item["dedup_hash"] for item in registros}
    considerados = sum(
        1 for item in registros if item["data_hora"].date() >= CORTE_FATO_FINANCEIRO
    )
    print("\n== Resumo do arquivo ==")
    print(f"  transações:                  {len(registros)}")
    print(f"  linhas de saldo/ignoradas:    {ignoradas}")
    print(f"  hashes únicos:                {len(hashes)}")
    print(f"  duplicatas internas:          {len(registros) - len(hashes)}")
    print(
        f"  a partir de {CORTE_FATO_FINANCEIRO.isoformat()} "
        f"(contam no calendário/despesas/DRE): {considerados} de {len(registros)}"
    )
    if considerados < len(registros):
        print(
            "  Os demais são gravados em raw_bs_cash para não perder o "
            "histórico, mas NÃO entram no fato_financeiro (esse período já "
            "é contado via a planilha histórico)."
        )


def gravar(registros, periodo):
    return importar_registros(
        registros=registros,
        tabela="raw_bs_cash",
        colunas=COLUNAS,
        conflito="(dedup_hash)",
        montar_linha=lambda item, conta_id: (
            [conta_id] + [item[coluna] for coluna in COLUNAS[1:]]
        ),
        conta_nome="BS Cash",
        fonte_log="Extrato BS Cash",
        periodo=periodo,
    )


def fluxo():
    opcoes = ler_opcoes(criar_parser("Importa extrato da conta BS Cash"))
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
