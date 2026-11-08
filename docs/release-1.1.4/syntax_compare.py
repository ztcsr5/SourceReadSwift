from pathlib import Path
import subprocess,json
from tree_sitter import Language,Parser
import tree_sitter_swift
R=Path(__file__).resolve().parents[2]
parser=Parser(Language(tree_sitter_swift.language()))
def errors(data):
 result=[]
 def walk(n):
  if n.type=='ERROR' or n.is_missing:result.append({'line':n.start_point[0]+1,'type':n.type,'sample':data[n.start_byte:n.end_byte].decode('utf8')[:80]})
  for c in n.children:walk(c)
 walk(parser.parse(data).root_node);return result
BASE='d8c3a1f0133b19014b9f5af983d16df9f0fa8985'
names=subprocess.check_output(['git','diff','--name-only',BASE],cwd=R).decode().splitlines()
names += subprocess.check_output(['git','ls-files','--others','--exclude-standard','SourceReadSwift','SourceReadSwiftTests'],cwd=R).decode().splitlines()
rows=[]
for n in names:
 if not n.endswith('.swift'):continue
 old=subprocess.run(['git','show',BASE+':'+n],cwd=R,capture_output=True).stdout
 before=errors(old);after=errors((R/n).read_bytes())
 rows.append({'file':n,'baseline_errors':len(before),'current_errors':len(after),'new_samples':after[:3] if len(after)>len(before) else []})
Path('F:/SourceReadSwift/release-1.1.4/syntax-comparison.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(rows,ensure_ascii=False))
