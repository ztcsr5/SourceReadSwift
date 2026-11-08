import zipfile
import io
import sys
sys.path.insert(0, 'scripts')
import verify_reader_quality as q

arts = q.github.api('actions/runs/42288900692/artifacts')['artifacts']
evidence_art = next(a for a in arts if 'tab-evidence' in a['name'])
print("Downloading tab-evidence...")
data = q.github.signed_download(f"actions/artifacts/{evidence_art['id']}/zip")
z = zipfile.ZipFile(io.BytesIO(data))
print("Files in tab-evidence:")
for name in z.namelist():
    print(" -", name)
