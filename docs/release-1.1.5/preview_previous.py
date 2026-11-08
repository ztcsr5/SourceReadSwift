from pathlib import Path
import io,json,zipfile
import ci
folder=ci.OUT/'preliminary-layout-6b75ae9';folder.mkdir(parents=True,exist_ok=True)
for a in ci.ci.api('actions/runs/41306881813/artifacts')['artifacts']:
    print(a['name'],a['size_in_bytes'])
    if a['name'].startswith('ios-test-'):
        archive=folder/'evidence.zip'
        if not archive.exists():archive.write_bytes(ci.ci.signed_download(f"actions/artifacts/{a['id']}/zip"))
        with zipfile.ZipFile(archive) as z:
            for member in z.namelist():
                p=Path(member)
                if 'ui-snapshots/' in member and p.suffix.lower() in ['.png','.json']:
                    (folder/p.name).write_bytes(z.read(member))
        print('Extracted',len(list(folder.glob('*.png'))),'preliminary images; NOT final commit evidence')
