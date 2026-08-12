#!/usr/bin/env python3
"""Testes sem rede do preparador de uma instalação independente."""

from __future__ import annotations

import base64
import importlib.util
import json
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "implantacao" / "preparar_nova_empresa.py"
SPEC = importlib.util.spec_from_file_location("preparar_nova_empresa", MODULE_PATH)
assert SPEC and SPEC.loader
implantacao = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(implantacao)


def jwt(payload: dict[str, object]) -> str:
    encode = lambda value: base64.urlsafe_b64encode(
        json.dumps(value, separators=(",", ":")).encode("utf-8")
    ).decode("ascii").rstrip("=")
    return f"{encode({'alg': 'HS256', 'typ': 'JWT'})}.{encode(payload)}.assinatura"


def esperar_erro(funcao, trecho: str) -> None:
    try:
        funcao()
    except implantacao.ValidacaoErro as exc:
        if trecho not in str(exc):
            raise AssertionError(f"erro inesperado: {exc}") from exc
    else:
        raise AssertionError(f"era esperado erro contendo: {trecho}")


def main() -> int:
    ref = "abcdefghijklmnopqrst"
    outra_ref = "qrstabcdefghijklmnop"
    chave_anon = jwt({"role": "anon", "ref": ref})
    chave_privada = jwt({"role": "service_role", "ref": ref})

    with tempfile.TemporaryDirectory() as tmp:
        raiz = Path(tmp)
        client = raiz / "supabase-client.js"
        client.write_text(
            '(function () {\r\n'
            '  const SUPABASE_URL = "https://antigo.supabase.co";\r\n'
            '  const SUPABASE_ANON_KEY = "antiga";\r\n'
            '})();\r\n',
            encoding="utf-8",
            newline="",
        )
        obtido = implantacao.configurar_frontend(
            f"https://{ref}.supabase.co/",
            chave_anon,
            client,
        )
        if obtido != ref:
            raise AssertionError("project ref não foi extraído da URL")
        url_lida, chave_lida = implantacao.ler_configuracao(client)
        if url_lida != f"https://{ref}.supabase.co" or chave_lida != chave_anon:
            raise AssertionError("configuração do cliente ficou divergente")
        if b"\r\n" not in client.read_bytes():
            raise AssertionError("configurador alterou as quebras de linha do arquivo")

        migrations = raiz / "migrations"
        migrations.mkdir()
        (migrations / "20260101000000_base.sql").write_text("select 1;", encoding="utf-8")
        schema = raiz / "schema.sql"
        schema.write_text("CREATE TABLE public.teste (id bigint);\n" + "-" * 1200, encoding="utf-8")
        manifest = raiz / "manifest.json"
        manifest.write_text("{}", encoding="utf-8")
        registrado = implantacao.registrar_baseline(schema, manifest, migrations)
        cutoff = implantacao.validar_baseline(schema, manifest, migrations)
        if cutoff != "20260101000000" or registrado != cutoff:
            raise AssertionError("cutoff válido não foi registrado e reconhecido")
        seed = raiz / "bootstrap_config.sql"
        seed.write_text(
            "begin;\n"
            "insert into public.configuracao_empresa values (default);\n"
            "insert into public.configuracao_operacional values (default);\n"
            "insert into public.parametros values (default);\n"
            "insert into public.unidade values (default);\n"
            "insert into public.pagina_permissao values (default);\n"
            + "-" * 300
            + "\ncommit;\n",
            encoding="utf-8",
        )
        implantacao.validar_bootstrap_config(seed)
        registrado_manifest = json.loads(manifest.read_text(encoding="utf-8"))
        if (
            registrado != "20260101000000"
            or registrado_manifest.get("migration_cutoff") != registrado
            or not registrado_manifest.get("schema_sha256")
        ):
            raise AssertionError("registro do baseline ficou incompleto")

        esperar_erro(
            lambda: implantacao.validar_chave_publica(chave_privada, project_ref=ref),
            "proibidas",
        )
        esperar_erro(
            lambda: implantacao.validar_chave_publica(chave_anon, project_ref=outra_ref),
            "outro projeto",
        )
        esperar_erro(
            lambda: implantacao.validar_url("http://inseguro.supabase.co"),
            "URL HTTPS",
        )
        esperar_erro(
            lambda: implantacao.validar_baseline(raiz / "ausente.sql", manifest, migrations),
            "baseline DDL ausente",
        )
        schema.write_text(
            "CREATE TABLE public.teste (id bigint);\nCOPY public.teste FROM stdin;\n" + "-" * 1200,
            encoding="utf-8",
        )
        esperar_erro(
            lambda: implantacao.validar_baseline(schema, manifest, migrations),
            "contém dados",
        )
        esperar_erro(
            lambda: implantacao.validar_bootstrap_config(raiz / "seed-ausente.sql"),
            "seed neutro ausente",
        )
        seed.write_text(
            seed.read_text(encoding="utf-8") + "\ninsert into public.raw_bb values (default);",
            encoding="utf-8",
        )
        esperar_erro(
            lambda: implantacao.validar_bootstrap_config(seed),
            "dados operacionais proibidos",
        )

    print("IMPLANTACAO_TESTS_OK frontend=1 secrets=2 baseline=4 seed=3")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
