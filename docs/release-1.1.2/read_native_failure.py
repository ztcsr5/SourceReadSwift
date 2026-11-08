from pathlib import Path
import re
p=Path('F:/SourceReadSwift/release-1.1.2/native-in-progress.log')
lines=p.read_text(encoding='utf8',errors='replace').splitlines()
for i,line in enumerate(lines):
    if any(s in line for s in ['Native tab runtime:', 'Test Suite', 'Test Case', 'error:', 'Timed out', '##[error]', 'cancelled']):
        print(i,line[:1200])
for i,line in enumerate(lines):
    if '##[error]' in line and ('cancel' in line or 'timeout' in line.lower()):
        print('\n'.join(lines[max(0,i-35):i+2]))
end=next((i for i,l in enumerate(lines) if 'Preserve iOS26 runtime evidence' in l),len(lines))
print('LAST ACTIVITY BEFORE ARTIFACT\n'+'\n'.join(lines[max(0,end-18):end])[:12000])
