#!/usr/bin/env python3
"""Importa extrato do Banco do Brasil com validação antes da transação."""

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
    parse_data_formatos,
    parse_valor_brasileiro,
    validar_leitura,
)


LINHAS_NAO_TRANSACAO = {"Saldo Anterior", "Saldo do dia", "S A L D O"}
# Em agosto de 2026 o BB parou de mandar o sinal negativo nos débitos: o que
# separa entrada de saída é o sufixo "C"/"D" do próprio campo Valor, presente
# nos dois formatos. "Tipo Lançamento" não serve de substituto — no export
# novo ele vem "Entrada" até nas saídas.
SINAL_POR_SUFIXO = {"C": 1, "D": -1}
ROTULOS_FUNDO_BB = {"Aplicação Fundo BB", "BB RF LP Selic"}
CABECALHOS = {"Data", "Lançamento", "Detalhes", "N° documento", "Valor", "Tipo Lançamento"}
COLUNAS = [
    "conta_id", "data", "data_raw", "lancamento", "detalhes",
    "n_documento", "valor", "tipo_lancamento", "dedup_hash",
]


def parse_valor_bb(valor_raw):
    numero = parse_valor_brasileiro(valor_raw)
    if numero is None:
        return None
    sinal = SINAL_POR_SUFIXO.get(str(valor_raw or "").strip()[-1:].upper())
    if sinal is None:
        return numero
    return sinal * abs(numero) if numero else 0.0


def ler_csv(caminho, opcoes):
    registros = []
    rejeicoes: list[Rejeicao] = []
    saldos_anteriores = []
    saldos_finais = []
    total_movimentos = 0.0
    ignoradas = 0
    total = 0
    with abrir_csv_validado(
        caminho,
        encoding="latin-1",
        delimiter=",",
        cabecalhos_obrigatorios=CABECALHOS,
    ) as reader:
        for row in reader:
            total += 1
            lancamento = campo(row, "Lançamento")
            if lancamento in LINHAS_NAO_TRANSACAO:
                valor_saldo = parse_valor_bb(campo(row, "Valor"))
                if lancamento == "Saldo Anterior":
                    saldos_anteriores.append(valor_saldo)
                elif lancamento == "S A L D O":
                    saldos_finais.append(valor_saldo)
                ignoradas += 1
                continue

            data_raw = campo(row, "Data")
            valor_raw = campo(row, "Valor")
            data = parse_data_formatos(data_raw, ("%d/%m/%Y",))
            valor = parse_valor_bb(valor_raw)
            motivos = []
            if data is None:
                motivos.append("data inválida")
            if valor is None:
                motivos.append("valor inválido")
            if not lancamento:
                motivos.append("lançamento ausente")
            adicionar_rejeicao(rejeicoes, reader.line_num, motivos)
            if motivos:
                continue

            total_movimentos += valor

            numero_documento = campo(row, "N° documento")
            detalhes = campo(row, "Detalhes")
            # O BB pode trocar o rótulo e o documento da mesma aplicação
            # quando o lançamento provisório é consolidado dias depois.
            # Para este produto, data + valor formam a identidade estável.
            if lancamento in ROTULOS_FUNDO_BB and valor < 0:
                base = f"{data.isoformat()}|FUNDO_BB_RF_LP_SELIC|{valor:.2f}"
            else:
                # O valor entra normalizado, e não como veio no arquivo: o
                # mesmo lançamento reexportado no formato novo ("1.234,56 D"
                # em vez de "-1.234,56 D") precisa cair no mesmo hash, senão
                # duplica.
                base = (
                    f"{data_raw}|{lancamento}|{numero_documento}"
                    f"|{valor:.2f}|{detalhes}"
                )
            registros.append({
                "data": data,
                "data_raw": data_raw,
                "lancamento": lancamento,
                "detalhes": detalhes,
                "n_documento": numero_documento,
                "valor": valor,
                "tipo_lancamento": campo(row, "Tipo Lançamento"),
                "dedup_hash": hashlib.md5(base.encode("utf-8")).hexdigest(),
            })

    motivos_saldo = []
    if len(saldos_anteriores) != 1 or len(saldos_finais) != 1:
        motivos_saldo.append(
            "extrato deve conter exatamente um Saldo Anterior e um S A L D O"
        )
    elif saldos_anteriores[0] is None or saldos_finais[0] is None:
        motivos_saldo.append("saldo anterior ou saldo final inválido")
    elif abs(
        saldos_anteriores[0] + total_movimentos - saldos_finais[0]
    ) > 0.01:
        motivos_saldo.append(
            "saldo final não confere com saldo anterior + movimentos"
        )
    adicionar_rejeicao(rejeicoes, 1, motivos_saldo)

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
    print("\n== Resumo do arquivo ==")
    print(f"  transações:          {len(registros)}")
    print(f"  linhas de saldo:     {ignoradas}")
    print(f"  hashes únicos:       {len(hashes)}")
    print(f"  duplicatas internas: {len(registros) - len(hashes)}")
    print(
        "  tipos:               "
        f"{dict(Counter(item['tipo_lancamento'] for item in registros))}"
    )


def gravar(registros, periodo):
    return importar_registros(
        registros=registros,
        tabela="raw_bb",
        colunas=COLUNAS,
        conflito="(dedup_hash)",
        montar_linha=lambda item, conta_id: (
            [conta_id] + [item[coluna] for coluna in COLUNAS[1:]]
        ),
        fonte_log="Extrato BB",
        periodo=periodo,
        fonte_chave="bb",
    )


def fluxo():
    opcoes = ler_opcoes(criar_parser("Importa extrato do Banco do Brasil"))
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
