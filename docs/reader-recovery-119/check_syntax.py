from pathlib import Path
import json,subprocess
from tree_sitter import Language,Parser
import tree_sitter_swift

ROOT=Path(__file__).resolve().parents[2]
parser=Parser(Language(tree_sitter_swift.language()))
changed=subprocess.check_output(['git','-C',str(ROOT),'diff','--name-only']).decode().splitlines()
changed+=subprocess.check_output(['git','-C',str(ROOT),'ls-files','--others','--exclude-standard','SourceReadSwift','SourceReadSwiftTests']).decode().splitlines()
result=[]
for name in sorted(set(changed)):
    if not name.endswith('.swift'):continue
    data=(ROOT/name).read_bytes();tree=parser.parse(data);errors=[]
    def visit(node):
        if node.type=='ERROR' or node.is_missing:
            errors.append({'line':node.start_point[0]+1,'type':node.type,'sample':data[node.start_byte:node.end_byte].decode('utf8')[:120]})
        for child in node.children:visit(child)
    visit(tree.root_node)
    result.append({'file':name,'parse_errors':errors})
(Path(__file__).parent/'syntax-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(result,ensure_ascii=False,indent=2))
raise SystemExit(1 if any(x['parse_errors'] for x in result) else 0)
