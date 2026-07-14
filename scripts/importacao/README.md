# Importação de dados

## Preparação

Na raiz do repositório, instale as versões registradas:

```powershell
python -m pip install -r requirements.txt
```

Para uma importação real, forneça `DATABASE_URL` por variável de ambiente ou
por um arquivo `.env` local e ignorado pelo Git. Nunca registre credenciais no
repositório.

## Ponto de entrada único

`rodar_importacoes.bat` é o clique único para o dia a dia: varre
`%USERPROFILE%\Downloads` pelos padrões de nome de arquivo conhecidos (Stone
extrato/vendas/recebíveis, BB e BS Cash), chama `importar.py` para cada
arquivo encontrado e move o CSV importado para a respectiva pasta
`relatorio-*-old`. Um padrão sem arquivo correspondente é simplesmente
pulado; o processo só para se uma importação falhar.

`importar.py` é o dispatcher: recebe um único CSV, detecta o tipo comparando
o cabeçalho do arquivo com o `CABECALHOS` de cada módulo (`01_importar_extrato_stone.py`,
`02_importar_vendas_stone.py`, `03_importar_recebiveis_stone.py`,
`04_importar_bb.py`, `05_importar_bs_cash.py`) e delega a leitura/gravação
para o módulo correspondente. Ele não duplica a lógica de parsing e
validação — cada módulo continua com suas próprias regras e pode ser
chamado diretamente também. Para adicionar uma nova origem no futuro, basta
criar um módulo seguindo o mesmo padrão (`CABECALHOS`, `COLUNAS`, `ler_csv`,
`resumo`, `gravar`) e registrá-lo em `REGISTRO`, em `importar.py`.

## Fluxo seguro

Execute primeiro com `--dry-run`. O arquivo inteiro é validado sem conexão com
o banco:

```powershell
python scripts/importacao/importar.py arquivo.csv --dry-run
```

Os importadores conferem:

- extensão, conteúdo e cabeçalhos do CSV;
- tipos de datas, números e chaves obrigatórias;
- período mínimo e máximo observado;
- unidade operacional, atualmente restrita a `PRAIA`;
- rejeições de linhas, com tolerância zero antes da gravação.

Os limites opcionais de período usam o formato `AAAA-MM-DD`:

```powershell
python scripts/importacao/importar.py arquivo.csv `
  --dry-run --periodo-inicio 2026-07-01 --periodo-fim 2026-07-31
```

Em uma carga real, inserção, recálculo e registro em `log_carga` são uma única
transação. O refresh do painel ocorre após o commit. Se o refresh falhar, o
processo retorna erro para que o BAT não arquive o CSV; uma nova execução é
segura por causa da deduplicação.

## Códigos de saída

- `0`: concluído;
- `1`: erro inesperado ou de arquivo;
- `2`: validação recusou o CSV (inclui cabeçalho não reconhecido por nenhum
  importador, ou reconhecido por mais de um);
- `3`: falha operacional de dependência, banco ou refresh.

`13_importar_historico.py` permanece uma carga única e não é executado pelo
BAT nem pelo dispatcher.

O extrato da conta BS Cash (`05_importar_bs_cash.py`) é gravado por inteiro em
`raw_bs_cash`, mas `fato_financeiro` só passa a considerá-lo a partir de
2026-01-01 (mesmo corte usado para Stone/BB) — período anterior já é contado
pela carga única do histórico. Ver a migration
`20260725000000_importa_bs_cash.sql` para o motivo.
