import sqlite3,json
from pathlib import Path
p=Path('F:/AntigravityData/.gemini/antigravity/conversations/2a8bc56d-a010-4246-b869-51077d557ea9.db')
with sqlite3.connect(p.as_uri()+'?mode=ro',uri=True) as db:
    row=db.execute('select count(*),max(idx) from steps').fetchone()
print(json.dumps({'db':str(p),'steps':row[0],'last_idx':row[1],'already_reviewed_through':5178,'newer_steps':row[1]>5178},ensure_ascii=False))
