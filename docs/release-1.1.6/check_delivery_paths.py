from pathlib import Path
import hashlib
for folder in [Path('C:/Users/Edc21/Desktop'),Path('F:/SourceReadSwift/release-1.1.5')]:
 print('FOLDER',folder,'exists',folder.exists())
 pattern='*SourceReadSwift*' if folder.name=='Desktop' else '*.ipa'
 for p in (folder.glob(pattern) if folder.name=='Desktop' else folder.rglob(pattern)):
  if p.is_file():print(p,p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest() if p.suffix=='.ipa' else '')
