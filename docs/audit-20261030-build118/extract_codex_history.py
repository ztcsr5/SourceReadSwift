"""Extract visible user/assistant events, without reasoning or tool payloads."""
from pathlib import Path
import collections
import hashlib
import json
import re

OUT = Path(__file__).resolve().parent
IDS = ('01a15848-1328-7f23-a24e-509b26c7c1a9', '01a1870b-2d3c-7541-97a5-cf146a4daee9')

def redact(text):
    text = re.sub(r'https://[^\s/@]+:[^\s/@]+@', 'https://[REDACTED]@', text)
    return re.sub(r'\b(?:ghp_|github_pat_|gho_)[A-Za-z0-9_]+', '[REDACTED_TOKEN]', text)

def visible_text(content):
    if isinstance(content,str): return content
    if isinstance(content,list): return '\n'.join(filter(None,(visible_text(x) for x in content)))
    if isinstance(content,dict):
        if isinstance(content.get('text'),str): return content['text']
        if 'content' in content:return visible_text(content['content'])
    return ''

def main():
    roots = (Path('F:/Codex/.codex/sessions'), Path('C:/Users/Edc21/.codex/sessions'))
    manifest = []
    for thread in IDS:
        paths = {}
        for root in roots:
            if root.exists():
                for path in root.rglob('*.jsonl'):
                    if thread in path.name:
                        paths[str(path.resolve()).casefold()] = path.resolve()
        events = []
        seen = set()
        for path in sorted(paths.values()):
            count = 0
            kinds = collections.Counter()
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for number, raw in enumerate(stream, 1):
                    digest.update(raw)
                    data = json.loads(raw)
                    kind = data.get('type')
                    payload = data.get('payload', {})
                    kinds[kind] += 1
                    if kind != 'event_msg':
                        continue
                    if payload.get('type')=='item_completed':
                        item=payload.get('item',{})
                        if item.get('type') not in ('UserMessage','AgentMessage'):continue
                        role='user' if item['type']=='UserMessage' else 'assistant'
                        text=visible_text(item.get('content',''))
                    elif payload.get('type') in ('user_message','agent_message'):
                        role='user' if payload['type']=='user_message' else 'assistant'
                        text=payload.get('message','')
                    else:continue
                    if not isinstance(text, str) or not text:
                        continue
                    key = (data.get('timestamp'), role, text)
                    if key in seen:
                        continue
                    seen.add(key)
                    events.append({'timestamp': data.get('timestamp'), 'role': role, 'text': redact(text), 'source': str(path), 'line': number})
                    count += 1
            manifest.append({'thread':thread,'path':str(path),'bytes':path.stat().st_size,'sha256':digest.hexdigest(),'lines':number,'visible_events':count,'kinds':dict(kinds)})
        events.sort(key=lambda x: x['timestamp'] or '')
        (OUT/f'codex-{thread}-visible.json').write_text(json.dumps(events,ensure_ascii=False,indent=2),encoding='utf-8')
        (OUT/f'codex-{thread}-requests.md').write_text('\n\n'.join(f"## {e['timestamp']} / {Path(e['source']).name}:{e['line']}\n\n{e['text']}" for e in events if e['role']=='user'),encoding='utf-8')
        print(thread, 'files',len(paths),'events',len(events),'users',sum(e['role']=='user' for e in events))
        for e in [e for e in events if e['role']=='user'][-12:]:
            print(e['timestamp'],e['text'][:240].replace('\n',' '))
    (OUT/'codex-history-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__ == '__main__':
    main()
