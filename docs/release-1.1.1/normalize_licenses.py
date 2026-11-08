from pathlib import Path
root=Path(__file__).resolve().parents[2]
for p in (root/'SourceReadSwift/Resources/Fonts').glob('*-OFL.txt'):
 p.write_text('\n'.join(x.rstrip() for x in p.read_text(encoding='utf8').splitlines())+'\n',encoding='utf8')
