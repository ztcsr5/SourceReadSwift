# -*- coding: utf-8 -*-
"""Import source JSON with the phone's current pairing capability.

python tools/lan_import.py sources.json --base http://PHONE_ADDRESS:8080
The key is read from SOURCE_READ_LAN_TOKEN or a non-echoing prompt, never argv.
"""
import argparse
import getpass
import json
import os
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def client():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


def request(opener, base, path, token, payload=None):
    headers = {'X-SourceRead-Token': token}
    if payload is not None:
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(base + path, data=payload, headers=headers)
    try:
        with opener.open(req, timeout=120) as response:
            return response.status, response.read(2000).decode('utf-8', 'replace')
    except urllib.error.HTTPError as error:
        return error.code, error.read(2000).decode('utf-8', 'replace')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('path')
    ap.add_argument('--base', required=True)
    ap.add_argument('--limit', type=int, default=1_700_000)
    args = ap.parse_args()
    url = urllib.parse.urlsplit(args.base)
    if url.scheme != 'http' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
        ap.error('--base must be the phone HTTP origin without credentials, path or query')
    base = args.base.rstrip('/')
    if not 1024 <= args.limit <= 12 * 1024 * 1024:
        ap.error('--limit must be between 1024 and 12582912 bytes')
    token = (os.environ.get('SOURCE_READ_LAN_TOKEN') or getpass.getpass('Phone pairing key: ')).strip().lower()
    if len(token) != 32 or any(c not in '0123456789abcdef' for c in token):
        ap.error('Copy the current 32-character key from the phone')
    opener = client()
    status, _ = request(opener, base, '/api/status', token)
    if status != 200:
        raise SystemExit(f'Pairing/connection failed: HTTP {status}; no imports attempted')
    with open(args.path, encoding='utf-8-sig') as stream:
        data = json.load(stream)
    if isinstance(data, dict):
        data = data.get('sources', [data])
    if not isinstance(data, list) or not data:
        raise SystemExit('Expected a non-empty source array or source-library snapshot')
    batches, current, size = [], [], 2
    for source in data:
        if not isinstance(source, dict) or not source.get('bookSourceUrl') or not source.get('bookSourceName'):
            raise SystemExit('Each source needs bookSourceUrl and bookSourceName; no imports attempted')
        encoded = json.dumps(source, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        if len(encoded) + 2 > args.limit:
            raise SystemExit('One source exceeds batch limit; no imports attempted')
        if current and size + len(encoded) + 1 > args.limit:
            batches.append(current)
            current, size = [], 2
        current.append(encoded)
        size += len(encoded) + 1
    if current:
        batches.append(current)
    print(f'sources={len(data)} batches={len(batches)}')
    imported = 0
    for i, batch in enumerate(batches, 1):
        payload = b'[' + b','.join(batch) + b']'
        status, body = request(opener, base, '/api/sources/import', token, payload)
        print(f'batch {i}/{len(batches)} bytes={len(payload)} -> HTTP {status}')
        if status != 200:
            # A failed response can follow a partial server-side change.
            # Do not repeat requests or print raw source headers and secrets.
            raise SystemExit(f'Import not confirmed; check the phone before retrying. Earlier confirmed: {imported} sources')
        if json.loads(body).get('ok') is not True:
            raise SystemExit('Import not confirmed; inspect phone diagnostics before retrying')
        imported += len(batch)
    print(f'confirmed_imported={imported}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(f'{type(error).__name__}: import stopped; check the phone before retrying')
