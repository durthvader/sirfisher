#!/usr/bin/env python3
"""Importa vendas Stone com validação integral antes da transação."""

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
    valor_informado_invalido,
)


FORMATOS_DATA = ("%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M", "%d/%m/%Y")
CABECALHOS = {
    "DOCUMENTO", "STONECODE", "DATA DA VENDA", "BANDEIRA", "PRODUTO",
    "STONE ID", "N DE PARCELAS", "VALOR BRUTO", "VALOR LIQUIDO",
    "DESCONTO DE MDR", "DESCONTO DE ANTECIPACAO", "DESCONTO UNIFICADO",
    "N DO CARTAO", "MEIO DE CAPTURA", "N DE SERIE", "ULTIMO STATUS",
    "DATA DO ULTIMO STATUS",
}
COLUNAS = [
    "conta_id", "documento", "stonecode", "data_venda", "bandeira",
    "produto", "stone_id", "n_parcelas", "valor_bruto", "valor_liquido",
    "desconto_mdr", "desconto_antecipacao", "desconto_unificado", "n_cartao",
    "meio_captura", "n_serie", "ultimo_status", "data_ultimo_status",
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
            stone_id = campo(row, "STONE ID")
            data_raw = campo(row, "DATA DA VENDA")
            parcelas_raw = campo(row, "N DE PARCELAS")
            bruto_raw = campo(row, "VALOR BRUTO")
            liquido_raw = campo(row, "VALOR LIQUIDO")
            mdr_raw = campo(row, "DESCONTO DE MDR")
            antecipacao_raw = campo(row, "DESCONTO DE ANTECIPACAO")
            unificado_raw = campo(row, "DESCONTO UNIFICADO")
            status_data_raw = campo(row, "DATA DO ULTIMO STATUS")

            data_venda = parse_datetime_formatos(data_raw, FORMATOS_DATA)
            n_parcelas = parse_inteiro(parcelas_raw)
            valor_bruto = parse_valor_brasileiro(bruto_raw)
            valor_liquido = parse_valor_brasileiro(liquido_raw)
            desconto_mdr = parse_valor_brasileiro(mdr_raw)
            desconto_antecipacao = parse_valor_brasileiro(antecipacao_raw)
            desconto_unificado = parse_valor_brasileiro(unificado_raw)
            data_ultimo_status = parse_datetime_formatos(status_data_raw, FORMATOS_DATA)

            motivos = []
            if not stone_id:
                motivos.append("STONE ID ausente")
            if data_venda is None:
                motivos.append("data da venda inválida")
            if valor_bruto is None:
                motivos.append("valor bruto inválido")
            if valor_liquido is None:
                motivos.append("valor líquido inválido")
            opcionais = (
                ("número de parcelas inválido", parcelas_raw, n_parcelas),
                ("desconto MDR inválido", mdr_raw, desconto_mdr),
                ("desconto de antecipação inválido", antecipacao_raw, desconto_antecipacao),
                ("desconto unificado inválido", unificado_raw, desconto_unificado),
                ("data do último status inválida", status_data_raw, data_ultimo_status),
            )
            motivos.extend(
                mensagem
                for mensagem, bruto, convertido in opcionais
                if valor_informado_invalido(bruto, convertido)
            )
            adicionar_rejeicao(rejeicoes, reader.line_num, motivos)
            if motivos:
                continue

            registros.append({
                "documento": campo(row, "DOCUMENTO"),
                "stonecode": campo(row, "STONECODE"),
                "data_venda": data_venda,
                "bandeira": campo(row, "BANDEIRA"),
                "produto": campo(row, "PRODUTO"),
                "stone_id": stone_id,
                "n_parcelas": n_parcelas,
                "valor_bruto": valor_bruto,
                "valor_liquido": valor_liquido,
                "desconto_mdr": desconto_mdr,
                "desconto_antecipacao": desconto_antecipacao,
                "desconto_unificado": desconto_unificado,
                "n_cartao": campo(row, "N DO CARTAO"),
                "meio_captura": campo(row, "MEIO DE CAPTURA"),
                "n_serie": campo(row, "N DE SERIE"),
                "ultimo_status": campo(row, "ULTIMO STATUS"),
                "data_ultimo_status": data_ultimo_status,
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
    ids = {item["stone_id"] for item in registros}
    print("\n== Resumo do arquivo ==")
    print(f"  registros:           {len(registros)}")
    print(f"  STONE IDs únicos:    {len(ids)}")
    print(f"  duplicatas internas: {len(registros) - len(ids)}")
    print(f"  status:              {dict(Counter(item['ultimo_status'] for item in registros))}")


def gravar(registros, periodo):
    return importar_registros(
        registros=registros,
        tabela="raw_stone_vendas",
        colunas=COLUNAS,
        conflito="(stone_id)",
        montar_linha=lambda item, conta_id: (
            [conta_id] + [item[coluna] for coluna in COLUNAS[1:]]
        ),
        conta_nome="Stone",
        fonte_log="Vendas Stone",
        periodo=periodo,
    )


def fluxo():
    opcoes = ler_opcoes(criar_parser("Importa vendas Stone"))
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
