"""Read-only source inventory and graphify structural extraction."""
import collections
import hashlib
import json
import re
from pathlib import Path

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]

def main():
    from graphify.detect import detect
    from graphify.extract import extract
    files = sorted(ROOT.glob('SourceReadSwift/**/*.swift')) + sorted(ROOT.glob('SourceReadSwiftTests/**/*.swift'))
    inventory = []
    for path in files:
        text = path.read_text(encoding='utf-8-sig')
        inventory.append({
            'path': path.relative_to(ROOT).as_posix(),
            'lines': len(text.splitlines()),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'imports': re.findall(r'^import (\w+)', text, re.M),
            'declarations': re.findall(r'^\s*(?:(?:private|public|final|internal|indirect)\s+)*(?:struct|class|enum|actor|protocol)\s+(\w+)', text, re.M),
            'test_functions': len(re.findall(r'\bfunc test\w*\s*\(', text)),
            'state_wrappers': len(re.findall(r'@(State|StateObject|AppStorage)\b', text)),
        })
    (OUT/'source-inventory.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2),encoding='utf-8')
    source = [x for x in inventory if x['path'].startswith('SourceReadSwift/')]
    modules = collections.defaultdict(lambda: {'files':0,'lines':0})
    for item in source:
        module = '/'.join(item['path'].split('/')[:3])
        modules[module]['files'] += 1
        modules[module]['lines'] += item['lines']
    md = ['# Source inventory', '', 'Structural inventory, not a claim of line-by-line semantic verification.', '', '| Module | Files | Lines |','|---|---:|---:|']
    md.extend(f'| {k} | {v["files"]} | {v["lines"]} |' for k,v in sorted(modules.items()))
    md.extend(['','## Largest sources','','| File | Lines | State wrappers |','|---|---:|---:|'])
    md.extend(f'| {x["path"]} | {x["lines"]} | {x["state_wrappers"]} |' for x in sorted(source,key=lambda x:x['lines'],reverse=True)[:20])
    (OUT/'INVENTORY.md').write_text('\n'.join(md)+'\n',encoding='utf-8')
    target = ROOT/'SourceReadSwift/Features/Reader'
    detection = detect(target)
    (OUT/'graph-detection.json').write_text(json.dumps(detection,ensure_ascii=False,indent=2),encoding='utf-8')
    ast = extract(list(target.glob('*.swift')))
    (OUT/'graph-ast.json').write_text(json.dumps(ast,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'source_files':len(source),'source_lines':sum(x['lines'] for x in source),'test_files':len(files)-len(source),'test_functions':sum(x['test_functions'] for x in inventory),'ast_nodes':len(ast['nodes']),'ast_edges':len(ast['edges'])}))

if __name__ == '__main__':
    main()
