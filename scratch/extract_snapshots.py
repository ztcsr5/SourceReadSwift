import sys
import zipfile
import io
from pathlib import Path
sys.path.insert(0, 'scripts')
import verify_reader_quality as q

arts = q.github.api('actions/runs/42288900692/artifacts')['artifacts']
art = next(a for a in arts if 'snapshots' in a['name'])
print(f"Downloading {art['name']} ({art['size_in_bytes']} bytes)...")
data = q.github.signed_download(f"actions/artifacts/{art['id']}/zip")
z = zipfile.ZipFile(io.BytesIO(data))
out_dir = Path("F:/SourceReadSwift/reader-quality-137/verification/snapshots-c906860")
out_dir.mkdir(parents=True, exist_ok=True)
for name in z.namelist():
    if '18-reader' in name or 'gesture' in name or 'return' in name:
        print("Found:", name)
        z.extract(name, out_dir)
print("Done extracting.")
