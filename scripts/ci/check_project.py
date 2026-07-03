#!/usr/bin/env python3
"""Quality gates sem dependências externas para o sirfisher-app."""

from __future__ import annotations

import argparse
import ast
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TEXT_SUFFIXES = {".html", ".css", ".js", ".py", ".sql", ".md", ".yml", ".yaml", ".json", ".ps1", ".bat", ".txt"}
FORBIDDEN_TRACKED_SUFFIXES = {".csv", ".tsv", ".xlsx", ".xls", ".dump", ".backup"}
SECRET_PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"),
    "GitHub token": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    "database password in URL": re.compile(r"postgres(?:ql)?://[^:\s]+:[^@\s]+@", re.I),
    "service role assignment": re.compile(r"SUPABASE_SERVICE_ROLE_KEY\s*=\s*['\"][^'\"]+", re.I),
}


def fail(message: str) -> None:
    raise AssertionError(message)


def repository_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    ).stdout
    return [ROOT / item.decode("utf-8") for item in result.split(b"\0") if item]


def check_python() -> int:
    files = sorted(ROOT.rglob("*.py"))
    files = [path for path in files if ".git" not in path.parts]
    for path in files:
        ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
    return len(files)


def check_javascript(require_node: bool) -> tuple[int, int]:
    node = shutil.which("node")
    if not node:
        if require_node:
            fail("Node.js não encontrado para validar JavaScript")
        return 0, 0

    external = sorted((ROOT / "assets").glob("*.js"))
    inline_count = 0
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        for path in external:
            subprocess.run([node, "--check", str(path)], check=True, capture_output=True)
        for page in sorted(ROOT.glob("*.html")):
            html = page.read_text(encoding="utf-8")
            scripts = re.findall(
                r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", html, flags=re.I | re.S
            )
            for index, source in enumerate(scripts, start=1):
                target = tmp_path / f"{page.stem}-{index}.js"
                target.write_text(source, encoding="utf-8")
                subprocess.run([node, "--check", str(target)], check=True, capture_output=True)
                inline_count += 1
    return len(external), inline_count


def check_links() -> tuple[int, set[str]]:
    pages = sorted(ROOT.glob("*.html"))
    assets: set[str] = set()
    missing: list[str] = []
    for page in pages:
        html = page.read_text(encoding="utf-8")
        for value in re.findall(r"(?:src|href)=['\"]([^'\"]+)['\"]", html, flags=re.I):
            if value.startswith(("http://", "https://", "#", "data:")):
                continue
            relative = value.split("#", 1)[0].split("?", 1)[0]
            if not relative:
                continue
            target = (page.parent / relative).resolve()
            if not target.exists():
                missing.append(f"{page.name}: {value}")
            if relative.startswith("assets/"):
                assets.add(relative.replace("\\", "/"))
    if missing:
        fail("Links locais ausentes: " + ", ".join(missing))
    return len(pages), assets


def check_accessibility() -> int:
    pages = sorted(ROOT.glob("*.html"))
    problems: list[str] = []
    for page in pages:
        html = page.read_text(encoding="utf-8")
        checks = {
            "idioma pt-BR": re.search(r'<html\s+[^>]*lang=["\']pt-BR["\']', html, re.I),
            "viewport": re.search(r'<meta\s+[^>]*name=["\']viewport["\']', html, re.I),
            "título": re.search(r'<title>\s*[^<]+\s*</title>', html, re.I),
            "título principal": re.search(r'<h1(?:\s|>)', html, re.I),
            "conteúdo principal": re.search(r'<main(?:\s|>)', html, re.I),
            "CSS compartilhado": 'href="assets/accessibility.css"' in html,
            "JS compartilhado": 'src="assets/accessibility.js"' in html,
        }
        for label, passed in checks.items():
            if not passed:
                problems.append(f"{page.name}: {label}")

    style_sources = pages + sorted((ROOT / "assets").glob("*.css"))
    for path in style_sources:
        content = path.read_text(encoding="utf-8")
        if re.search(r"outline\s*:\s*none", content, re.I):
            problems.append(f"{path.relative_to(ROOT).as_posix()}: foco suprimido")

    if problems:
        fail("Acessibilidade estática: " + ", ".join(problems))
    return len(pages)


def check_contracts() -> int:
    sources = "\n".join(
        path.read_text(encoding="utf-8-sig", errors="ignore")
        for path in [ROOT / "supabase" / "baseline" / "database.types.ts"]
        + sorted((ROOT / "supabase" / "migrations").glob("*.sql"))
    )
    references: set[str] = set()
    for page in ROOT.glob("*.html"):
        html = page.read_text(encoding="utf-8")
        references.update(re.findall(r"\.from\(['\"]([a-zA-Z0-9_]+)['\"]\)", html))
        references.update(re.findall(r"\.rpc\(['\"]([a-zA-Z0-9_]+)['\"]", html))
    missing = sorted(name for name in references if name not in sources)
    if missing:
        fail("Contratos Supabase não versionados: " + ", ".join(missing))
    return len(references)


def check_secrets(files: list[Path]) -> int:
    findings: list[str] = []
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        if path.name == ".env" or path.name.startswith(".env."):
            findings.append(f"arquivo proibido: {relative}")
            continue
        if path.suffix.lower() in FORBIDDEN_TRACKED_SUFFIXES:
            findings.append(f"dado bruto versionado: {relative}")
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES or not path.exists():
            continue
        content = path.read_text(encoding="utf-8-sig", errors="ignore")
        for label, pattern in SECRET_PATTERNS.items():
            if pattern.search(content):
                findings.append(f"{label}: {relative}")
    if findings:
        fail("Possíveis segredos/dados sensíveis: " + ", ".join(findings))
    return len(files)


def workflow_expected_files() -> set[str]:
    workflow = (ROOT / ".github" / "workflows" / "deploy-pages.yml").read_text(encoding="utf-8")
    match = re.search(r'expected_files="\$\(printf.*?\\n(.*?)\)"', workflow, flags=re.S)
    if not match:
        fail("Allowlist expected_files não encontrada no workflow de Pages")
    return set(
        re.findall(r"[A-Za-z0-9_./-]+\.(?:html|js|css)", match.group(1))
    )


def check_artifact(assets: set[str]) -> int:
    expected = workflow_expected_files()
    required = {page.name for page in ROOT.glob("*.html")} | assets
    if expected != required:
        missing = sorted(required - expected)
        extra = sorted(expected - required)
        fail(f"Allowlist Pages divergente; ausentes={missing}; extras={extra}")
    forbidden = [item for item in expected if Path(item).suffix.lower() in FORBIDDEN_TRACKED_SUFFIXES]
    if forbidden:
        fail("Artefato contém tipo proibido: " + ", ".join(forbidden))
    return len(expected)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-node", action="store_true")
    args = parser.parse_args()
    tracked = repository_files()
    python_count = check_python()
    js_external, js_inline = check_javascript(args.require_node)
    page_count, assets = check_links()
    accessibility_count = check_accessibility()
    contract_count = check_contracts()
    secret_count = check_secrets(tracked)
    artifact_count = check_artifact(assets)
    print(
        "QUALITY_OK "
        f"python={python_count} js_external={js_external} js_inline={js_inline} "
        f"pages={page_count} a11y={accessibility_count} contracts={contract_count} scanned={secret_count} "
        f"artifact={artifact_count}"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, subprocess.CalledProcessError) as exc:
        print(f"QUALITY_ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
