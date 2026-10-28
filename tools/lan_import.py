# -*- coding: utf-8 -*-
"""Import a Legado book-source JSON file into the app over LAN, in size-safe batches.

Usage:
  python lan_import.py <sources.json> [--base http://192.168.31.205:8080]
"""
import argparse, json, sys, urllib.request, urllib.error

def post(base, payload_bytes, timeout=120):
    req = urllib.request.Request(base + '/api/sources/import', data=payload_bytes,
                                 headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(400).decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        return e.code, e.read(400).decode('utf-8', 'replace')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('path')
    ap.add_argument('--base', default='http://192.168.31.205:8080')
    ap.add_argument('--limit', type=int, default=1_700_000)
    a = ap.parse_args()
    data = json.load(open(a.path, encoding='utf-8'))
    if isinstance(data, dict):
        data = [data]
    batches, cur, size = [], [], 0
    for s in data:
        b = json.dumps(s, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        if cur and size + len(b) + 2 > a.limit:
            batches.append(cur); cur, size = [], 0
        cur.append(b); size += len(b) + 2
    if cur:
        batches.append(cur)
    print(f'sources={len(data)} batches={len(batches)}')
    ok = fail = 0
    for i, batch in enumerate(batches, 1):
        payload = b'[' + b','.join(batch) + b']'
        st, body = post(a.base, payload)
        print(f'batch {i}/{len(batches)} bytes={len(payload)} -> {st} {body[:120]}')
        if st == 200:
            ok += len(batch); continue
        for one in batch:  # retry individually to isolate the bad source
            st2, body2 = post(a.base, b'[' + one + b']')
            if st2 == 200:
                ok += 1
            else:
                fail += 1
                print('  FAIL', one[:120].decode('utf-8', 'replace'), st2, body2[:120])
    print(f'imported={ok} failed={fail}')
    try:
        with urllib.request.urlopen(a.base + '/api/status', timeout=15) as r:
            print('status', r.read(200).decode('utf-8', 'replace'))
    except Exception as e:
        print('status check failed', e)

if __name__ == '__main__':
    main()
