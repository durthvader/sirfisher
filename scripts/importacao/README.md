# Importação de dados

## Preparação

Na raiz do repositório, instale as versões registradas:

```powershell
python -m pip install -r requirements.txt
```

Para uma importação real, forneça `DATABASE_URL` por variável de ambiente ou
por um arquivo `.env` local e ignorado pelo Git. Nunca registre credenciais no
repositório.

## Fluxo seguro

Execute primeiro com `--dry-run`. O arquivo inteiro é validado sem conexão com
o banco:

```powershell
python scripts/importacao/01_importar_extrato_stone.py arquivo.csv --dry-run
```

Os importadores conferem:

- extensão, conteúdo e cabeçalhos do CSV;
- tipos de datas, números e chaves obrigatórias;
- período mínimo e máximo observado;
- unidade operacional, atualmente restrita a `PRAIA`;
- rejeições de linhas, com tolerância zero antes da gravação.

Os limites opcionais de período usam o formato `AAAA-MM-DD`:

```powershell
python scripts/importacao/02_importar_vendas_stone.py arquivo.csv `
  --dry-run --periodo-inicio 2026-07-01 --periodo-fim 2026-07-31
```

Em uma carga real, inserção, recálculo e registro em `log_carga` são uma única
transação. O refresh do painel ocorre após o commit. Se o refresh falhar, o
processo retorna erro para que o BAT não arquive o CSV; uma nova execução é
segura por causa da deduplicação.

## Códigos de saída

- `0`: concluído;
- `1`: erro inesperado ou de arquivo;
- `2`: validação recusou o CSV;
- `3`: falha operacional de dependência, banco ou refresh.

Os arquivos BAT existentes continuam sendo os pontos de entrada para os quatro
fluxos regulares. `13_importar_historico.py` permanece uma carga única e não é
executado pelos BATs.
