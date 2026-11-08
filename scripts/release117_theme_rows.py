"""Style native Section rows with theme paper; inspect first, --apply writes. Usage: python -X utf8 scripts/release117_theme_rows.py [--apply]"""
from pathlib import Path
import json,sys
from tree_sitter import Language,Parser
import tree_sitter_swift
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('F:/SourceReadSwift/release-1.1.7/theme17')
parser=Parser(Language(tree_sitter_swift.language()))
names=[*sorted((ROOT/'SourceReadSwift/Features/Settings').glob('*.swift')),
       *sorted((ROOT/'SourceReadSwift/Features/SourceManager').glob('*.swift'))]
rows=[]
for p in names:
    data=p.read_bytes();tree=parser.parse(data);edits=[]
    def visit(node):
        if node.type=='call_expression' and node.named_children and node.named_children[0].type=='simple_identifier' and data[node.named_children[0].start_byte:node.named_children[0].end_byte]==b'Section':
            # A Section call can be the receiver of an existing row background.
            end=node.end_byte;tail=data[end:end+180]
            if b'.listRowBackground(' not in tail.split(b'\n\n',1)[0]:
                line_start=data.rfind(b'\n',0,node.start_byte)+1
                indent=data[line_start:node.start_byte]
                if not indent.strip():
                    newline=b'\r\n' if b'\r\n' in data else b'\n'
                    edits.append((end,newline+indent+b'.listRowBackground(AppTheme.card)'))
                    rows.append({'file':str(p.relative_to(ROOT)),'section_line':node.start_point.row+1,'header':data[node.start_byte:node.end_byte].splitlines()[0].decode('utf-8')})
        for child in node.named_children:visit(child)
    visit(tree.root_node)
    if '--apply' in sys.argv and edits:
        baseline=OUT/'BASELINE'/p.relative_to(ROOT)
        assert baseline.exists()
        for end,value in sorted(edits,reverse=True):data=data[:end]+value+data[end:]
        p.write_bytes(data)
(OUT/'section-rows.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
print('Sections',len(rows),'files',len(set(r['file'] for r in rows)))
if '--apply' not in sys.argv:
    print(json.dumps(rows[:12],ensure_ascii=False,indent=2))
