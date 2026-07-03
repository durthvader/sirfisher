#!/usr/bin/env python3
"""Importa recebíveis Stone com validação integral antes da transação."""

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
    parse_data_formatos,
    parse_datetime_formatos,
    parse_inteiro,
    parse_valor_brasileiro,
    validar_leitura,
    valor_informado_invalido,
)


FORMATOS_DATA = ("%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y")
CABECALHOS = {
    "DOCUMENTO", "STONECODE", "CATEGORIA", "DATA DA VENDA",
    "DATA DE VENCIMENTO", "DATA DE VENCIMENTO ORIGINAL", "BANDEIRA", "PRODUTO",
    "STONE ID", "QTD DE PARCELAS", "Nº DA PARCELA", "VALOR BRUTO",
    "VALOR LÍQUIDO", "DESCONTO DE MDR", "DESCONTO DE ANTECIPAÇÃO",
    "DESCONTO UNIFICADO", "ÚLTIMO STATUS", "DATA DO ÚLTIMO STATUS",
    "ENTRADAS BRUTAS", "SAÍDAS BRUTAS",
}
COLUNAS = [
    "conta_id", "documento", "stonecode", "categoria", "data_venda",
    "data_vencimento", "data_vencimento_original", "bandeira", "produto",
    "stone_id", "qtd_parcelas", "n_parcela", "valor_bruto", "valor_liquido",
    "desconto_mdr", "desconto_antecipacao", "desconto_unificado",
    "ultimo_status", "data_ultimo_status", "entradas_brutas", "saidas_brutas",
]


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
            bruto = {
                "data_venda": campo(row, "DATA DA VENDA"),
                "data_vencimento": campo(row, "DATA DE VENCIMENTO"),
                "data_vencimento_original": campo(row, "DATA DE VENCIMENTO ORIGINAL"),
                "qtd_parcelas": campo(row, "QTD DE PARCELAS"),
                "n_parcela": campo(row, "Nº DA PARCELA"),
                "valor_bruto": campo(row, "VALOR BRUTO"),
                "valor_liquido": campo(row, "VALOR LÍQUIDO"),
                "desconto_mdr": campo(row, "DESCONTO DE MDR"),
                "desconto_antecipacao": campo(row, "DESCONTO DE ANTECIPAÇÃO"),
                "desconto_unificado": campo(row, "DESCONTO UNIFICADO"),
                "data_ultimo_status": campo(row, "DATA DO ÚLTIMO STATUS"),
                "entradas_brutas": campo(row, "ENTRADAS BRUTAS"),
                "saidas_brutas": campo(row, "SAÍDAS BRUTAS"),
            }
            convertido = {
                "data_venda": parse_datetime_formatos(bruto["data_venda"], FORMATOS_DATA),
                "data_vencimento": parse_data_formatos(bruto["data_vencimento"], FORMATOS_DATA),
                "data_vencimento_original": parse_data_formatos(
                    bruto["data_vencimento_original"], FORMATOS_DATA
                ),
                "qtd_parcelas": parse_inteiro(bruto["qtd_parcelas"]),
                "n_parcela": parse_inteiro(bruto["n_parcela"]),
                "valor_bruto": parse_valor_brasileiro(bruto["valor_bruto"]),
                "valor_liquido": parse_valor_brasileiro(bruto["valor_liquido"]),
                "desconto_mdr": parse_valor_brasileiro(bruto["desconto_mdr"]),
                "desconto_antecipacao": parse_valor_brasileiro(bruto["desconto_antecipacao"]),
                "desconto_unificado": parse_valor_brasileiro(bruto["desconto_unificado"]),
                "data_ultimo_status": parse_datetime_formatos(
                    bruto["data_ultimo_status"], FORMATOS_DATA
                ),
                "entradas_brutas": parse_valor_brasileiro(bruto["entradas_brutas"]),
                "saidas_brutas": parse_valor_brasileiro(bruto["saidas_brutas"]),
            }
            stone_id = campo(row, "STONE ID")
            motivos = []
            if not stone_id:
                motivos.append("STONE ID ausente")
            if convertido["n_parcela"] is None:
                motivos.append("número da parcela inválido")
            if convertido["valor_liquido"] is None:
                motivos.append("valor líquido inválido")
            datas_linha = (
                convertido["data_vencimento"],
                convertido["data_venda"],
                convertido["data_vencimento_original"],
            )
            if not any(datas_linha):
                motivos.append("nenhuma data de referência válida")
            rotulos = {
                "data_venda": "data da venda inválida",
                "data_vencimento": "data de vencimento inválida",
                "data_vencimento_original": "data de vencimento original inválida",
                "qtd_parcelas": "quantidade de parcelas inválida",
                "valor_bruto": "valor bruto inválido",
                "desconto_mdr": "desconto MDR inválido",
                "desconto_antecipacao": "desconto de antecipação inválido",
                "desconto_unificado": "desconto unificado inválido",
                "data_ultimo_status": "data do último status inválida",
                "entradas_brutas": "entradas brutas inválidas",
                "saidas_brutas": "saídas brutas inválidas",
            }
            motivos.extend(
                mensagem
                for chave, mensagem in rotulos.items()
                if valor_informado_invalido(bruto[chave], convertido[chave])
            )
            adicionar_rejeicao(rejeicoes, reader.line_num, motivos)
            if motivos:
                continue

            registros.append({
                "documento": campo(row, "DOCUMENTO"),
                "stonecode": campo(row, "STONECODE"),
                "categoria": campo(row, "CATEGORIA"),
                "bandeira": campo(row, "BANDEIRA"),
                "produto": campo(row, "PRODUTO"),
                "stone_id": stone_id,
                "ultimo_status": campo(row, "ÚLTIMO STATUS"),
                **convertido,
            })

    datas_periodo = []
    for item in registros:
        datas_periodo.append(
            item["data_vencimento"]
            or (item["data_venda"].date() if item["data_venda"] else None)
            or item["data_vencimento_original"]
        )
    periodo = validar_leitura(
        registros=registros,
        total_linhas=total,
        rejeicoes=rejeicoes,
        datas=datas_periodo,
        opcoes=opcoes,
    )
    return registros, periodo


def resumo(registros):
    chaves = {(item["stone_id"], item["n_parcela"]) for item in registros}
    print("\n== Resumo do arquivo ==")
    print(f"  registros:           {len(registros)}")
    print(f"  chaves únicas:       {len(chaves)}")
    print(f"  duplicatas internas: {len(registros) - len(chaves)}")
    print(f"  status:              {dict(Counter(item['ultimo_status'] for item in registros))}")


def gravar(registros, periodo):
    return importar_registros(
        registros=registros,
        tabela="raw_stone_recebiveis",
        colunas=COLUNAS,
        conflito="(stone_id, n_parcela)",
        montar_linha=lambda item, conta_id: (
            [conta_id] + [item[coluna] for coluna in COLUNAS[1:]]
        ),
        conta_nome="Stone",
        fonte_log="Recebíveis Stone",
        periodo=periodo,
    )


def fluxo():
    opcoes = ler_opcoes(criar_parser("Importa recebíveis Stone"))
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
