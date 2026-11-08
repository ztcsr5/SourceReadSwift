from pathlib import Path
p=Path(__file__).with_name('RECOVERY.md')
p.write_text(p.read_text(encoding='utf8').rstrip()+'\n',encoding='utf8')
