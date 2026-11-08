from pathlib import Path
p = Path(__file__).with_name('ci.py')
s = p.read_text(encoding='utf8')
lines = s.splitlines()
for i, line in enumerate(lines):
    if "if log.exists() and mode" in line:
        lines[i] = ' ' * 5 + "if log.exists() and mode != 'brief':"
        lines[i+1] = ' ' * 6 + lines[i+1].lstrip()
        lines[i+2] = ' ' * 6 + lines[i+2].lstrip()
p.write_text('\n'.join(lines)+'\n', encoding='utf8')
