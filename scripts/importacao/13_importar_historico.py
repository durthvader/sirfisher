#!/usr/bin/env python3
# =====================================================================
# SIR FISHER - ETAPA 1 - Arquivo 13
# Carga UNICA do HISTORICO (arquivo historico_uniao.csv)
#
# COMO RODAR:
#   Simulacao (nao toca no banco):
#       python 13_importar_historico.py historico_uniao.csv --dry-run
#   De verdade (precisa do .env com DATABASE_URL):
#       python 13_importar_historico.py historico_uniao.csv
#
# Este CSV ja vem limpo (valor decimal, datas ISO, classificacao
# embutida). E uma carga unica: rodar de novo nao duplica.
# =====================================================================

import sys, csv, hashlib
from datetime import datetime

csv.field_size_limit(10_000_000)

def parse_valor(s):
    s = (s or '').strip()
    if s == '':
        return None
    try:
        return float(s)            # CSV ja vem em formato decimal limpo
    except ValueError:
        return None

def parse_data(s):
    s = (s or '').strip()
    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d'):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None

def v(row, key):
    val = row.get(key)
    if val is None:
        return None
    val = str(val).strip()
    return val if val != '' else None

def ler_csv(caminho):
    registros = []
    with open(caminho, encoding='utf-8', newline='') as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            seq = v(row, 'seq')
            base = "|".join([
                seq or '', v(row,'empresa') or '', v(row,'data_iso') or '',
                v(row,'valor') or '', v(row,'destino') or '',
                v(row,'destino_documento') or '', v(row,'origem') or ''
            ])
            dedup_hash = hashlib.md5(base.encode('utf-8')).hexdigest()
            registros.append({
                'seq':                 int(seq) if seq and seq.isdigit() else None,
                'empresa':             v(row,'empresa'),
                'movimentacao':        v(row,'movimentacao'),
                'tipo':                v(row,'tipo'),
                'valor':               parse_valor(v(row,'valor')),
                'saldo_antes':         parse_valor(v(row,'saldo_antes')),
                'saldo_depois':        parse_valor(v(row,'saldo_depois')),
                'tarifa':              v(row,'tarifa'),
                'data_hora':           parse_data(v(row,'data_iso')),
                'data_raw':            v(row,'data_iso'),
                'situacao':            v(row,'situacao'),
                'nosso_numero':        v(row,'nosso_numero'),
                'destino':             v(row,'destino'),
                'destino_documento':   v(row,'destino_documento'),
                'destino_instituicao': v(row,'destino_instituicao'),
                'origem':              v(row,'origem'),
                'origem_documento':    v(row,'origem_documento'),
                'origem_instituicao':  v(row,'origem_instituicao'),
                'categoria':           v(row,'categoria'),
                'dre_grupo':           v(row,'dre_grupo'),
                'fornecedor':          v(row,'fornecedor'),
                'ajuste_manual':       v(row,'ajuste_manual'),
                'detalhamento':        v(row,'detalhamento'),
                'dedup_hash':          dedup_hash,
            })
    return registros

COLUNAS = ['seq','empresa','movimentacao','tipo','valor','saldo_antes','saldo_depois',
           'tarifa','data_hora','data_raw','situacao','nosso_numero','destino',
           'destino_documento','destino_instituicao','origem','origem_documento',
           'origem_instituicao','categoria','dre_grupo','fornecedor','ajuste_manual',
           'detalhamento','dedup_hash']

def resumo(registros):
    from collections import Counter
    print(f"  linhas lidas:        {len(registros)}")
    hashes = set(r['dedup_hash'] for r in registros)
    print(f"  hashes unicos:       {len(hashes)} (duplicatas no arquivo: {len(registros)-len(hashes)})")
    datas = [r['data_hora'] for r in registros if r['data_hora']]
    if datas:
        print(f"  periodo:             {min(datas).date()} a {max(datas).date()}")
    com_cat = sum(1 for r in registros if r['categoria'])
    print(f"  com categoria:       {com_cat} ({100*com_cat//max(len(registros),1)}%)")
    print(f"  por empresa:         {dict(Counter(r['empresa'] for r in registros).most_common(6))} ...")

def gravar(registros):
    import os
    import psycopg2
    from psycopg2.extras import execute_values
    try:
        from dotenv import load_dotenv
        load_dotenv()
    except ImportError:
        pass

    url = os.environ.get('DATABASE_URL')
    if not url:
        print("ERRO: variavel DATABASE_URL nao encontrada (arquivo .env).")
        sys.exit(1)

    conn = psycopg2.connect(url)
    cur = conn.cursor()
    valores = [[reg[c] for c in COLUNAS] for reg in registros]
    sql = f"insert into raw_historico ({', '.join(COLUNAS)}) values %s " \
          f"on conflict (dedup_hash) do nothing"
    execute_values(cur, sql, valores, page_size=1000)
    inseridos = cur.rowcount
    conn.commit()
    cur.close(); conn.close()
    print(f"  novas linhas inseridas: {inseridos}")
    print(f"  ja existiam (ignoradas): {len(registros) - inseridos}")

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    if not args:
        print("Uso: python 13_importar_historico.py <historico_uniao.csv> [--dry-run]")
        sys.exit(1)

    caminho = args[0]
    print(f"Lendo: {caminho}")
    registros = ler_csv(caminho)
    print("\n== Resumo do arquivo ==")
    resumo(registros)

    if dry:
        print("\n[DRY-RUN] Nada foi gravado no banco.")
    else:
        print("\n== Gravando no banco (pode levar alguns segundos) ==")
        gravar(registros)
    print("\nOK.")

if __name__ == '__main__':
    main()
