"""Infraestrutura compartilhada dos importadores do Sir Fisher.

Este módulo não executa importações ao ser carregado. Dependências de banco são
importadas somente quando uma gravação real é solicitada, permitindo validar
arquivos com ``--dry-run`` sem credenciais ou acesso ao Supabase.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Callable, Iterable, Iterator, Mapping, Sequence


UNIDADE_PADRAO = "PRAIA"
UNIDADES_SUPORTADAS = frozenset({UNIDADE_PADRAO})
LIMITE_REJEICOES_EXIBIDAS = 12
_IDENTIFICADOR_SQL = re.compile(r"^[a-z_][a-z0-9_]*$")
_CONFLITO_SQL = re.compile(r"^\([a-z0-9_, ]+\)$")


class ImportacaoErro(RuntimeError):
    """Erro esperado e seguro para exibição no terminal."""

    codigo_saida = 1


class ValidacaoErro(ImportacaoErro):
    codigo_saida = 2


class ErroOperacional(ImportacaoErro):
    codigo_saida = 3


@dataclass(frozen=True)
class OpcoesImportacao:
    arquivo: Path
    dry_run: bool
    unidade: str
    periodo_inicio: date | None
    periodo_fim: date | None


@dataclass(frozen=True)
class Rejeicao:
    linha: int
    motivo: str


@dataclass(frozen=True)
class ResultadoImportacao:
    inseridos: int
    ignorados: int
    periodo_inicio: date | None
    periodo_fim: date | None


def criar_parser(descricao: str, *, arquivo_nargs: str | None = None) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=descricao)
    parser.add_argument("arquivo", type=Path, nargs=arquivo_nargs, help="arquivo CSV a importar")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="valida e resume o CSV sem acessar o banco",
    )
    parser.add_argument(
        "--unidade",
        default=os.environ.get("SIRFISHER_UNIDADE", UNIDADE_PADRAO),
        help=f"unidade operacional (padrão: {UNIDADE_PADRAO})",
    )
    parser.add_argument(
        "--periodo-inicio",
        type=_data_iso,
        help="menor data esperada no formato AAAA-MM-DD",
    )
    parser.add_argument(
        "--periodo-fim",
        type=_data_iso,
        help="maior data esperada no formato AAAA-MM-DD",
    )
    return parser


def ler_opcoes(parser: argparse.ArgumentParser, argv: Sequence[str] | None = None) -> OpcoesImportacao:
    return opcoes_de_args(parser, parser.parse_args(argv))


def opcoes_de_args(parser: argparse.ArgumentParser, args: argparse.Namespace) -> OpcoesImportacao:
    unidade = validar_unidade(args.unidade)
    if args.periodo_inicio and args.periodo_fim and args.periodo_inicio > args.periodo_fim:
        parser.error("--periodo-inicio não pode ser posterior a --periodo-fim")
    return OpcoesImportacao(
        arquivo=args.arquivo,
        dry_run=args.dry_run,
        unidade=unidade,
        periodo_inicio=args.periodo_inicio,
        periodo_fim=args.periodo_fim,
    )


def _data_iso(valor: str) -> date:
    try:
        return datetime.strptime(valor, "%Y-%m-%d").date()
    except ValueError as exc:
        raise argparse.ArgumentTypeError("use o formato AAAA-MM-DD") from exc


def validar_unidade(valor: str) -> str:
    unidade = (valor or "").strip().upper()
    if unidade not in UNIDADES_SUPORTADAS:
        permitidas = ", ".join(sorted(UNIDADES_SUPORTADAS))
        raise ValidacaoErro(f"unidade inválida; valores permitidos: {permitidas}")
    return unidade


def campo(row: Mapping[str, object], chave: str) -> str | None:
    valor = row.get(chave)
    if valor is None:
        return None
    texto = str(valor).strip()
    return texto or None


def parse_valor_brasileiro(valor: object) -> float | None:
    if valor is None:
        return None
    limpo = re.sub(r"[^\d,.\-]", "", str(valor))
    if limpo in ("", "-", ".", ","):
        return None
    negativo = limpo.startswith("-")
    limpo = limpo.replace(".", "").replace(",", ".").lstrip("-")
    try:
        numero = float(limpo)
    except ValueError:
        return None
    return -numero if negativo else numero


def parse_valor_decimal(valor: object) -> float | None:
    texto = str(valor or "").strip()
    if not texto:
        return None
    try:
        return float(texto)
    except ValueError:
        return None


def parse_inteiro(valor: object) -> int | None:
    texto = str(valor or "").strip()
    try:
        return int(texto)
    except ValueError:
        return None


def parse_datetime_formatos(valor: object, formatos: Iterable[str]) -> datetime | None:
    texto = str(valor or "").strip()
    for formato in formatos:
        try:
            return datetime.strptime(texto, formato)
        except ValueError:
            continue
    return None


def parse_data_formatos(valor: object, formatos: Iterable[str]) -> date | None:
    data_hora = parse_datetime_formatos(valor, formatos)
    return data_hora.date() if data_hora else None


def valor_informado_invalido(bruto: object, convertido: object) -> bool:
    return campo({"valor": bruto}, "valor") is not None and convertido is None


def validar_arquivo(caminho: Path) -> Path:
    caminho = caminho.expanduser()
    if not caminho.exists():
        raise ValidacaoErro("arquivo não encontrado")
    if not caminho.is_file():
        raise ValidacaoErro("o caminho informado não é um arquivo")
    if caminho.suffix.lower() != ".csv":
        raise ValidacaoErro("o arquivo precisa ter extensão .csv")
    if caminho.stat().st_size == 0:
        raise ValidacaoErro("o arquivo CSV está vazio")
    return caminho


@contextmanager
def abrir_csv_validado(
    caminho: Path,
    *,
    encoding: str,
    delimiter: str,
    cabecalhos_obrigatorios: Iterable[str],
) -> Iterator[csv.DictReader]:
    arquivo = validar_arquivo(caminho)
    try:
        with arquivo.open(encoding=encoding, newline="") as handle:
            reader = csv.DictReader(handle, delimiter=delimiter)
            cabecalhos = list(reader.fieldnames or [])
            if not cabecalhos:
                raise ValidacaoErro("CSV sem cabeçalho")
            duplicados = sorted({h for h in cabecalhos if cabecalhos.count(h) > 1})
            if duplicados:
                raise ValidacaoErro("cabeçalhos duplicados: " + ", ".join(duplicados))
            ausentes = sorted(set(cabecalhos_obrigatorios) - set(cabecalhos))
            if ausentes:
                raise ValidacaoErro("cabeçalhos obrigatórios ausentes: " + ", ".join(ausentes))
            yield reader
    except UnicodeError as exc:
        raise ValidacaoErro("codificação do CSV incompatível com o importador") from exc
    except csv.Error as exc:
        raise ValidacaoErro("estrutura do CSV inválida") from exc


def adicionar_rejeicao(rejeicoes: list[Rejeicao], linha: int, motivos: Iterable[str]) -> None:
    lista = [motivo for motivo in motivos if motivo]
    if lista:
        rejeicoes.append(Rejeicao(linha=linha, motivo="; ".join(lista)))


def validar_leitura(
    *,
    registros: Sequence[Mapping[str, object]],
    total_linhas: int,
    rejeicoes: Sequence[Rejeicao],
    datas: Iterable[date | datetime | None],
    opcoes: OpcoesImportacao,
    ignoradas: int = 0,
) -> tuple[date, date]:
    if total_linhas == 0:
        raise ValidacaoErro("CSV sem linhas de dados")
    if rejeicoes:
        amostra = "; ".join(
            f"linha {item.linha}: {item.motivo}"
            for item in rejeicoes[:LIMITE_REJEICOES_EXIBIDAS]
        )
        restante = len(rejeicoes) - LIMITE_REJEICOES_EXIBIDAS
        complemento = f"; e mais {restante} rejeição(ões)" if restante > 0 else ""
        raise ValidacaoErro(
            f"{len(rejeicoes)} linha(s) rejeitada(s); nenhuma gravação foi feita. "
            f"{amostra}{complemento}"
        )
    if not registros:
        raise ValidacaoErro("nenhum registro válido encontrado")

    periodo = sorted(_como_data(item) for item in datas if item is not None)
    if not periodo:
        raise ValidacaoErro("nenhuma data válida encontrada para determinar o período")
    inicio, fim = periodo[0], periodo[-1]
    if opcoes.periodo_inicio and inicio < opcoes.periodo_inicio:
        raise ValidacaoErro(
            f"período começa em {inicio}, antes do limite {opcoes.periodo_inicio}"
        )
    if opcoes.periodo_fim and fim > opcoes.periodo_fim:
        raise ValidacaoErro(f"período termina em {fim}, após o limite {opcoes.periodo_fim}")

    print("\n== Validação prévia ==")
    print(f"  unidade:             {opcoes.unidade}")
    print(f"  linhas no CSV:       {total_linhas}")
    print(f"  linhas aceitas:      {len(registros)}")
    print(f"  linhas ignoradas:    {ignoradas}")
    print("  linhas rejeitadas:   0")
    print(f"  período validado:    {inicio} a {fim}")
    return inicio, fim


def _como_data(valor: date | datetime) -> date:
    return valor.date() if isinstance(valor, datetime) else valor


def importar_registros(
    *,
    registros: Sequence[Mapping[str, object]],
    tabela: str,
    colunas: Sequence[str],
    conflito: str,
    montar_linha: Callable[[Mapping[str, object], object | None], Sequence[object]],
    conta_nome: str | None,
    fonte_log: str | None,
    periodo: tuple[date, date] | None,
    page_size: int = 500,
) -> ResultadoImportacao:
    _validar_sql_estatico(tabela, colunas, conflito)
    if not registros:
        raise ValidacaoErro("nenhum registro para gravar")

    try:
        import psycopg2
        from psycopg2.extras import execute_values
    except ImportError as exc:
        raise ErroOperacional(
            "dependências ausentes; execute: python -m pip install -r requirements.txt"
        ) from exc

    url = _database_url()
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(url)
        conn.autocommit = False
        cur = conn.cursor()

        conta_id = None
        if conta_nome:
            cur.execute("select id from conta where nome = %s limit 1;", (conta_nome,))
            conta = cur.fetchone()
            if not conta:
                raise ErroOperacional(f"conta operacional não cadastrada: {conta_nome}")
            conta_id = conta[0]

        valores = [list(montar_linha(registro, conta_id)) for registro in registros]
        sql = (
            f"insert into {tabela} ({', '.join(colunas)}) values %s "
            f"on conflict {conflito} do nothing returning 1"
        )
        retorno = execute_values(cur, sql, valores, page_size=page_size, fetch=True)
        inseridos = len(retorno)

        if periodo:
            cur.execute(
                "select * from recalcular_saldo_fechamento(%s, %s, 0);",
                periodo,
            )
            cur.fetchall()
        if fonte_log:
            cur.execute("insert into log_carga (fontes) values (%s);", (fonte_log,))

        conn.commit()
        return ResultadoImportacao(
            inseridos=inseridos,
            ignorados=len(registros) - inseridos,
            periodo_inicio=periodo[0] if periodo else None,
            periodo_fim=periodo[1] if periodo else None,
        )
    except ImportacaoErro:
        if conn:
            conn.rollback()
        raise
    except Exception as exc:
        if conn:
            conn.rollback()
        raise ErroOperacional(_mensagem_banco("falha na transação de importação", exc)) from exc
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


def atualizar_painel() -> None:
    """Atualiza o painel; falhas são operacionais e geram código não zero."""
    try:
        import psycopg2
    except ImportError as exc:
        raise ErroOperacional(
            "dependências ausentes; execute: python -m pip install -r requirements.txt"
        ) from exc

    url = _database_url()
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(url)
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute("select refresh_painel();")
    except Exception as exc:
        raise ErroOperacional(_mensagem_banco("falha ao atualizar o painel", exc)) from exc
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


def imprimir_resultado(resultado: ResultadoImportacao) -> None:
    print(f"  novas linhas inseridas: {resultado.inseridos}")
    print(f"  já existiam (ignoradas): {resultado.ignorados}")
    if resultado.periodo_inicio and resultado.periodo_fim:
        print(
            "  saldo recalculado:      "
            f"{resultado.periodo_inicio} a {resultado.periodo_fim}"
        )
        print("  log de carga registrado.")


def executar_com_saida(main: Callable[[], None]) -> int:
    try:
        main()
        return 0
    except ImportacaoErro as exc:
        print(f"\nERRO: {exc}")
        return exc.codigo_saida
    except OSError as exc:
        print(f"\nERRO: falha ao acessar o arquivo ({exc.__class__.__name__})")
        return 1
    except Exception as exc:
        print(f"\nERRO inesperado: {exc.__class__.__name__}")
        return 1


def _database_url() -> str:
    try:
        from dotenv import load_dotenv

        load_dotenv()
    except ImportError:
        pass
    url = os.environ.get("DATABASE_URL")
    if not url:
        raise ErroOperacional("variável DATABASE_URL não encontrada")
    return url


def _validar_sql_estatico(tabela: str, colunas: Sequence[str], conflito: str) -> None:
    if not _IDENTIFICADOR_SQL.fullmatch(tabela):
        raise ValueError("nome de tabela inválido")
    if not colunas or any(not _IDENTIFICADOR_SQL.fullmatch(item) for item in colunas):
        raise ValueError("lista de colunas inválida")
    if not _CONFLITO_SQL.fullmatch(conflito):
        raise ValueError("cláusula de conflito inválida")


def _mensagem_banco(contexto: str, erro: Exception) -> str:
    codigo = getattr(erro, "pgcode", None)
    return f"{contexto} (código PostgreSQL {codigo})" if codigo else contexto
