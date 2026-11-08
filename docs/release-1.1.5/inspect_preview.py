from pathlib import Path
import zipfile,re
with zipfile.ZipFile(Path('F:/SourceReadSwift/release-1.1.5/preliminary-layout-6b75ae9/evidence.zip')) as z:
    for n in z.namelist():
        if n.endswith('.log'):
            text=z.read(n).decode('utf8',errors='replace')
            print(n)
            print('\n'.join(x for x in text.splitlines() if re.search(r'error:|failed|TEST |BUILD ',x))[-5000:])
