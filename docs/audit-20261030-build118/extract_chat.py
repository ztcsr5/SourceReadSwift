"""Read-only extraction of visible text from Antigravity SQLite protobuf payloads.

No generated schema is available: field numbers below are observed in this DB.
Only user text (19.2 / 19.3.1), assistant visible text (20.1), and tool
visible results (140.2.1) are extracted. Other fields are deliberately ignored.
"""
import hashlib
import json
import re
import sqlite3
from pathlib import Path

DB = Path('C:/Users/Edc21/.gemini/antigravity/conversations/2a8bc56d-a010-4246-b869-51077d557ea9.db')
OUT = Path(__file__).resolve().parent

def varint(data, offset):
    value = shift = 0
    while offset < len(data) and shift <= 70:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if not byte & 128:
            return value, offset
        shift += 7
    raise ValueError('invalid varint')

def fields(data):
    offset = 0
    result = []
    while offset < len(data):
        tag, offset = varint(data, offset)
        field, wire = tag >> 3, tag & 7
        if not field:
            raise ValueError('invalid field')
        if wire == 0:
            value, offset = varint(data, offset)
        elif wire in (1, 2, 5):
            if wire == 2:
                size, offset = varint(data, offset)
            else:
                size = 8 if wire == 1 else 4
            value = data[offset:offset + size]
            offset += size
            if len(value) != size:
                raise ValueError('truncated field')
        else:
            raise ValueError('unsupported wire')
        result.append((field, wire, value))
    return result

def at(data, number):
    return [v for f, w, v in fields(data) if f == number and w == 2]

def redact(text):
    text = re.sub(r'https://[^\s/@]+:[^\s/@]+@', 'https://[REDACTED]@', text)
    text = re.sub(r'\b(?:ghp_|github_pat_|gho_)[A-Za-z0-9_]+', '[REDACTED_TOKEN]', text)
    return text

def main():
    con = sqlite3.connect(DB.as_uri() + '?mode=ro', uri=True)
    con.execute('BEGIN')
    rows = con.execute('select idx,step_type,step_payload from steps order by idx').fetchall()
    records = []
    errors = []
    for idx, kind, payload in rows:
        try:
            values = []
            role = None
            if kind == 14:
                role = 'user'
                for message in at(payload, 19):
                    values = at(message, 2)
                    if not values:
                        values = [x for part in at(message, 3) for x in at(part, 1)]
            elif kind == 15:
                role = 'assistant'
                values = [x for message in at(payload, 20) for x in at(message, 1)]
            elif kind == 132 and idx >= 4594:
                role = 'tool'
                values = [x for message in at(payload, 140) for result in at(message, 2) for x in at(result, 1)]
            if role and values:
                text = redact('\n'.join(x.decode('utf-8') for x in values))
                records.append({'idx': idx, 'role': role, 'text': text})
        except (ValueError, UnicodeError) as exc:
            errors.append({'idx': idx, 'error': str(exc)})
    con.rollback()
    con.close()
    (OUT/'chat-visible-text.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
    for name, selection in [('chat-user-requests.md', [r for r in records if r['role']=='user']),
                            ('chat-build118.md', [r for r in records if r['idx'] >= 4594])]:
        (OUT/name).write_text('\n\n'.join(f"## Step {r['idx']} — {r['role']}\n\n{r['text']}" for r in selection), encoding='utf-8')
    manifest = {'db': str(DB.resolve()), 'db_size': DB.stat().st_size,
                'steps': len(rows), 'last_idx': rows[-1][0],
                'extracted_records': len(records), 'errors': errors,
                'note':'Read-only transaction; field-level visible-text extraction, not complete UI/attachment restoration.'}
    (OUT/'chat-extraction.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(manifest, ensure_ascii=False))

if __name__ == '__main__':
    main()
