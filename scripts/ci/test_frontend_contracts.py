#!/usr/bin/env python3
"""Contratos estaticos de desempenho e resiliencia do front-end."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise AssertionError(message)


def source(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8")


def require(content: str, fragment: str, message: str) -> None:
    if fragment not in content:
        fail(message)


def main() -> int:
    auth = source("assets/auth.js")
    config = source("assets/app-config.js")
    require(auth, "Promise.allSettled([appReady, sessionRequest])", "Auth voltou a serializar configuracao e sessao")
    require(auth, "PERMISSIONS_CACHE_TTL_MS", "Matriz de navegacao perdeu o cache curto de sessao")
    require(auth, "clearPermissionsCache", "Permissoes editadas nao invalidam o cache de navegacao")
    require(config, "CACHE_TTL_MS = 5 * 60 * 1000", "Configuracao publica perdeu o cache curto")
    require(config, "reload: () => load(true)", "Recarga administrativa precisa ignorar o cache")

    caixa = source("caixa.html")
    for fragment in (
        "CACHE_MESES",
        "CARGA_DADOS",
        ".gte('dia',inicioCurvaISO).lte('dia',fimCurvaISO)",
        ".gte('dia',HOJE).lte('dia',riscoFim)",
        "fluxoRisco",
        "PROJECAO_ERRO",
    ):
        require(caixa, fragment, f"Caixa perdeu contrato: {fragment}")
    if "app_painel_fluxo_caixa').select('*').order('dia'" in caixa:
        fail("Caixa voltou a baixar todo o fluxo historico sem limite")
    cor_conta = caixa.split("function corConta", 1)[1].split("function drawContas", 1)[0]
    for specific in ("stone", "brasil", "inter", "btg", "bnb"):
        if specific in cor_conta.lower():
            fail(f"Cor de conta voltou a depender de banco especifico: {specific}")

    expenses = source("despesas.html")
    require(expenses, "app_painel_composicao_despesa", "Despesas perdeu o historico agregado")
    require(expenses, ".eq('ano_mes',anoMes)", "Detalhe de despesas voltou a carregar todos os meses")
    if "fetchPaginado(()=>sb.from('app_mv_despesa_mensal').select('*')\n        .order('mes'" in expenses:
        fail("Despesas voltou a baixar todo o historico detalhado")

    sales = source("vendas.html")
    require(sales, "RENDER_SEQ", "Faturamento perdeu protecao de troca de mes")
    if sales.count("renderSeq!==RENDER_SEQ") < 3:
        fail("Graficos de faturamento podem aceitar respostas de um mes antigo")
    if "Em breve" in sales or "soon-card" in sales:
        fail("Faturamento voltou a exibir funcionalidades especulativas")

    guarded = {
        "gerente.html": "trocaSeq!==TROCA_SEQ",
        "conciliacao.html": "renderSeq!==RENDER_SEQ",
        "conciliacao_contabil.html": "renderSeq!==RENDER_SEQ",
        "contas_recorrentes.html": "loadSeq!==LOAD_SEQ",
        "venda_especie.html": "carregarSeq!==CARREGAR_SEQ",
    }
    for page, fragment in guarded.items():
        require(source(page), fragment, f"{page} perdeu protecao contra resposta obsoleta")

    calendar = source("calendario.html")
    for fragment in (
        "const carga=++CARGA_ATUAL",
        "if(carga!==CARGA_ATUAL)return",
        "listar_calendario_financeiro",
        "listar_despesas_dia",
        "listar_saldo_contas_dia",
        "pop.dataset.dia!==r.dia",
    ):
        require(calendar, fragment, f"Calendario perdeu contrato de regressao: {fragment}")

    print("FRONTEND_CONTRACTS_OK pages=8 cache=2 calendar=1")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as exc:
        print(f"FRONTEND_CONTRACTS_ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
