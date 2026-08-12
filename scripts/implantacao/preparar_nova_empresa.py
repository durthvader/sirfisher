#!/usr/bin/env python3
"""Configura e valida o front-end antes de uma implantação isolada.

A URL e a chave pública precisam existir no JavaScript porque o site estático
deve descobrir o Supabase antes do login. Este utilitário reduz a troca a um
comando validado e nunca aceita credenciais privadas.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[2]
CLIENT_PATH = ROOT / "assets" / "supabase-client.js"
BASELINE_PATH = ROOT / "supabase" / "baseline" / "schema.sql"
BOOTSTRAP_PATH = ROOT / "supabase" / "baseline" / "bootstrap_config.sql"
MANIFEST_PATH = ROOT / "supabase" / "baseline" / "manifest.json"
MIGRATIONS_PATH = ROOT / "supabase" / "migrations"
URL_PATTERN = re.compile(r'(const SUPABASE_URL = )("[^"]*")(;)')
KEY_PATTERN = re.compile(r'(const SUPABASE_ANON_KEY = )("[^"]*")(;)')
MIGRATION_PATTERN = re.compile(r"^(\d{14})_[a-z0-9_]+\.sql$")


class ValidacaoErro(RuntimeError):
    pass


def _jwt_payload(token: str) -> dict[str, object] | None:
    partes = token.split(".")
    if len(partes) != 3:
        return None
    try:
        payload = partes[1] + "=" * (-len(partes[1]) % 4)
        decoded = base64.urlsafe_b64decode(payload.encode("ascii"))
        valor = json.loads(decoded.decode("utf-8"))
    except (ValueError, UnicodeError, json.JSONDecodeError):
        return None
    return valor if isinstance(valor, dict) else None


def validar_url(url: str) -> tuple[str, str]:
    normalizada = url.strip().rstrip("/")
    parsed = urlsplit(normalizada)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.port
        or parsed.path
        or parsed.query
        or parsed.fragment
    ):
        raise ValidacaoErro("use a URL HTTPS da API, sem caminho, parâmetros ou credenciais")
    sufixo = ".supabase.co"
    if not parsed.hostname.endswith(sufixo):
        raise ValidacaoErro("use a URL padrão do projeto no domínio supabase.co")
    project_ref = parsed.hostname[: -len(sufixo)]
    if not re.fullmatch(r"[a-z0-9]{20}", project_ref):
        raise ValidacaoErro("a URL não contém um identificador de projeto Supabase válido")
    return normalizada, project_ref


def validar_chave_publica(chave: str, *, project_ref: str) -> str:
    valor = chave.strip()
    if not valor or re.search(r"\s", valor):
        raise ValidacaoErro("a chave pública está vazia ou contém espaços")
    if valor.startswith("sb_secret_") or "service_role" in valor.lower():
        raise ValidacaoErro("chaves secretas e service_role são proibidas no front-end")
    if valor.startswith("sb_publishable_"):
        if len(valor) < 30:
            raise ValidacaoErro("a chave publishable parece incompleta")
        return valor

    payload = _jwt_payload(valor)
    if payload and payload.get("role") == "service_role":
        raise ValidacaoErro("chaves secretas e service_role são proibidas no front-end")
    if not payload or payload.get("role") != "anon":
        raise ValidacaoErro("use uma chave publishable ou a chave legada anon")
    ref_chave = payload.get("ref")
    if ref_chave and ref_chave != project_ref:
        raise ValidacaoErro("a chave pública pertence a outro projeto Supabase")
    return valor


def ler_configuracao(path: Path = CLIENT_PATH) -> tuple[str, str]:
    conteudo = path.read_text(encoding="utf-8")
    urls = URL_PATTERN.findall(conteudo)
    chaves = KEY_PATTERN.findall(conteudo)
    if len(urls) != 1 or len(chaves) != 1:
        raise ValidacaoErro("assets/supabase-client.js não possui o formato esperado")
    return json.loads(urls[0][1]), json.loads(chaves[0][1])


def configurar_frontend(url: str, chave: str, path: Path = CLIENT_PATH) -> str:
    url_normalizada, project_ref = validar_url(url)
    chave_publica = validar_chave_publica(chave, project_ref=project_ref)
    conteudo = path.read_bytes().decode("utf-8")
    atualizado, trocas_url = URL_PATTERN.subn(
        lambda match: match.group(1) + json.dumps(url_normalizada) + match.group(3),
        conteudo,
    )
    atualizado, trocas_chave = KEY_PATTERN.subn(
        lambda match: match.group(1) + json.dumps(chave_publica) + match.group(3),
        atualizado,
    )
    if trocas_url != 1 or trocas_chave != 1:
        raise ValidacaoErro("assets/supabase-client.js não possui o formato esperado")

    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporario:
        temporario.write(atualizado.encode("utf-8"))
        temporario_path = Path(temporario.name)
    temporario_path.replace(path)
    return project_ref


def versoes_migrations(path: Path = MIGRATIONS_PATH) -> list[str]:
    versoes: list[str] = []
    for arquivo in sorted(path.glob("*.sql")):
        match = MIGRATION_PATTERN.fullmatch(arquivo.name)
        if not match:
            raise ValidacaoErro(f"migration com nome inválido: {arquivo.name}")
        versoes.append(match.group(1))
    if not versoes:
        raise ValidacaoErro("nenhuma migration foi encontrada")
    return versoes


def validar_baseline(
    schema_path: Path = BASELINE_PATH,
    manifest_path: Path = MANIFEST_PATH,
    migrations_path: Path = MIGRATIONS_PATH,
) -> str:
    if not schema_path.is_file() or schema_path.stat().st_size < 1024:
        raise ValidacaoErro(
            "baseline DDL ausente; gere supabase/baseline/schema.sql antes de criar o banco novo"
        )
    schema = schema_path.read_text(encoding="utf-8-sig", errors="strict")
    if not re.search(r"^CREATE (?:TABLE|FUNCTION|VIEW|SCHEMA)\b", schema, re.I | re.M):
        raise ValidacaoErro("schema.sql não parece conter um dump DDL")
    if re.search(r"^COPY\s+(?:public|private)\.", schema, re.I | re.M):
        raise ValidacaoErro("schema.sql contém dados; o baseline deve ser somente estrutural")

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidacaoErro("manifesto do baseline ausente ou inválido") from exc
    if (
        manifest.get("schema_file") != schema_path.name
        or manifest.get("schema_bytes") != schema_path.stat().st_size
        or manifest.get("schema_sha256") != hashlib.sha256(schema_path.read_bytes()).hexdigest()
    ):
        raise ValidacaoErro("schema.sql diverge do checksum registrado no manifesto")
    cutoff = str(manifest.get("migration_cutoff") or "")
    versoes = versoes_migrations(migrations_path)
    if cutoff not in versoes:
        raise ValidacaoErro("manifesto não informa uma migration_cutoff válida")
    if cutoff != versoes[-1]:
        raise ValidacaoErro(
            "há migrations posteriores ao baseline; gere um snapshot atualizado antes da nova implantação"
        )
    return cutoff


def validar_bootstrap_config(path: Path = BOOTSTRAP_PATH) -> None:
    if not path.is_file() or path.stat().st_size < 256:
        raise ValidacaoErro(
            "seed neutro ausente; gere supabase/baseline/bootstrap_config.sql sem dados financeiros"
        )
    conteudo = path.read_text(encoding="utf-8-sig")
    obrigatorios = (
        "public.configuracao_empresa",
        "public.configuracao_operacional",
        "public.parametros",
        "public.unidade",
        "public.pagina_permissao",
    )
    ausentes = [
        tabela
        for tabela in obrigatorios
        if not re.search(rf"\binsert\s+into\s+{re.escape(tabela)}\b", conteudo, re.I)
    ]
    if ausentes:
        raise ValidacaoErro("seed neutro incompleto; faltam: " + ", ".join(ausentes))
    proibidos = re.findall(
        r"\b(?:raw_[a-z0-9_]+|fato_financeiro|ajuste_manual|log_carga|"
        r"venda_especie|conta_recorrente_pagamento)\b",
        conteudo,
        re.I,
    )
    if proibidos or re.search(r"^COPY\s+", conteudo, re.I | re.M):
        raise ValidacaoErro("seed neutro referencia tabelas ou dados operacionais proibidos")


def registrar_baseline(
    schema_path: Path = BASELINE_PATH,
    manifest_path: Path = MANIFEST_PATH,
    migrations_path: Path = MIGRATIONS_PATH,
) -> str:
    if not schema_path.is_file() or schema_path.stat().st_size < 1024:
        raise ValidacaoErro("schema.sql não foi gerado ou está incompleto")
    schema_bytes = schema_path.read_bytes()
    schema_text = schema_bytes.decode("utf-8-sig")
    if not re.search(r"^CREATE (?:TABLE|FUNCTION|VIEW|SCHEMA)\b", schema_text, re.I | re.M):
        raise ValidacaoErro("schema.sql não parece conter um dump DDL")
    if re.search(r"^COPY\s+(?:public|private)\.", schema_text, re.I | re.M):
        raise ValidacaoErro("schema.sql contém dados e não pode ser registrado como baseline")

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidacaoErro("manifesto do baseline ausente ou inválido") from exc
    cutoff = versoes_migrations(migrations_path)[-1]
    manifest.update(
        {
            "generated_at": datetime.now(timezone.utc).date().isoformat(),
            "schema_file": schema_path.name,
            "schema_sha256": hashlib.sha256(schema_bytes).hexdigest(),
            "schema_bytes": len(schema_bytes),
            "migration_cutoff": cutoff,
        }
    )
    atualizado = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    with tempfile.NamedTemporaryFile(dir=manifest_path.parent, delete=False) as temporario:
        temporario.write(atualizado.encode("utf-8"))
        temporario_path = Path(temporario.name)
    temporario_path.replace(manifest_path)
    return cutoff


def validar_instalacao(project_ref_esperado: str) -> tuple[str, str]:
    url, chave = ler_configuracao()
    _, project_ref = validar_url(url)
    validar_chave_publica(chave, project_ref=project_ref)
    if project_ref != project_ref_esperado:
        raise ValidacaoErro(
            "o front-end ainda aponta para outro projeto Supabase; execute configurar primeiro"
        )
    cutoff = validar_baseline()
    validar_bootstrap_config()
    return project_ref, cutoff


def criar_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Prepara o front-end e valida os bloqueios de uma instalação nova."
    )
    comandos = parser.add_subparsers(dest="comando", required=True)
    configurar = comandos.add_parser("configurar", help="troca URL e chave pública do front-end")
    configurar.add_argument("--url", required=True, help="URL HTTPS da API do projeto novo")
    configurar.add_argument(
        "--chave-publica",
        required=True,
        help="chave publishable ou chave legada anon do projeto novo",
    )
    validar = comandos.add_parser("validar", help="executa o pré-flight da instalação")
    validar.add_argument(
        "--project-ref",
        required=True,
        help="identificador do projeto Supabase novo",
    )
    comandos.add_parser(
        "registrar-baseline",
        help=argparse.SUPPRESS,
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = criar_parser().parse_args(argv)
    if args.comando == "configurar":
        project_ref = configurar_frontend(args.url, args.chave_publica)
        print(f"FRONTEND_CONFIG_OK project_ref={project_ref}")
        print("A chave pública foi validada e não será exibida.")
        return 0

    if args.comando == "registrar-baseline":
        cutoff = registrar_baseline()
        print(f"BASELINE_REGISTRADO_OK migration_cutoff={cutoff}")
        return 0

    project_ref, cutoff = validar_instalacao(args.project_ref)
    print(f"NOVA_INSTALACAO_OK project_ref={project_ref} migration_cutoff={cutoff}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValidacaoErro) as exc:
        print(f"NOVA_INSTALACAO_ERRO: {exc}", file=sys.stderr)
        sys.exit(1)
