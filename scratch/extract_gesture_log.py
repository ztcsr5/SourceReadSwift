import zipfile
import io
import sys
from pathlib import Path
sys.path.insert(0, 'scripts')
import verify_reader_quality as q

arts = q.github.api('actions/runs/42288900692/artifacts')['artifacts']
evidence_art = next(a for a in arts if 'tab-evidence' in a['name'])
data = q.github.signed_download(f"actions/artifacts/{evidence_art['id']}/zip")
z = zipfile.ZipFile(io.BytesIO(data))
out_dir = Path("F:/SourceReadSwift/reader-quality-137/verification/snapshots-c906860")
out_dir.mkdir(parents=True, exist_ok=True)
z.extract("native-reader-gesture-test.log", out_dir)
print("Extracted native-reader-gesture-test.log")
