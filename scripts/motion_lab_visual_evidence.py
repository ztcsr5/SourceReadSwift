"""Collect screenshot evidence using bounded ZIP ranges, not XCTest's large videos.

Usage: python -X utf8 scripts/motion_lab_visual_evidence.py --head <SHA> --artifact <ID>
Reuses the existing GitHub transport; signed URLs and credentials are never logged.
"""
from pathlib import Path
import argparse
import io
import json
import re
import sys
import urllib.error
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'docs/reader-recovery-119'))
import ci_status as github


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--head', required=True)
    parser.add_argument('--artifact', required=True, type=int)
    options = parser.parse_args()
    if not re.fullmatch('[a-f0-9]{40}', options.head):
        raise ValueError('Expected a full commit SHA')
    metadata = github.api(f'actions/artifacts/{options.artifact}')
    if metadata['name'] != 'motion-lab-evidence-' + options.head:
        raise ValueError('Artifact does not match the requested tested head')
    url = f'https://api.github.com/repos/{github.REPO}/actions/artifacts/{options.artifact}/zip'
    try:
        urllib.request.build_opener(github.NoRedirect).open(urllib.request.Request(url, headers=github.HEADERS), timeout=30)
        raise RuntimeError('Expected a signed ZIP redirect')
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise RuntimeError(f'Artifact redirect failed: HTTP {error.code}') from None
        signed_url = error.headers['Location']
    with urllib.request.urlopen(urllib.request.Request(signed_url, headers={'Range': 'bytes=0-0'}), timeout=30) as response:
        if response.status != 206:
            raise RuntimeError('Artifact server does not support bounded ZIP reads')
        size = int(response.headers['Content-Range'].split('/')[-1])
        response.read()

    class RemoteArchive(io.RawIOBase):
        def __init__(self):
            self.position = 0

        def seek(self, offset, whence=0):
            self.position = offset + (size if whence == 2 else self.position if whence == 1 else 0)
            return self.position

        def tell(self):
            return self.position

        def read(self, count=-1):
            count = size - self.position if count < 0 else count
            if count > 64_000_000:
                raise ValueError('Requested artifact range exceeds the evidence limit')
            end = min(size - 1, self.position + count - 1)
            if end < self.position:
                return b''
            request = urllib.request.Request(signed_url, headers={'Range': f'bytes={self.position}-{end}'})
            with urllib.request.urlopen(request, timeout=60) as response:
                if response.status != 206:
                    raise RuntimeError('Artifact range ignored')
                content = response.read(count + 1)
            if len(content) > count:
                raise ValueError('Artifact response exceeded its requested range')
            self.position += len(content)
            return content

    out = Path('F:/SourceReadSwift/motion-lab') / options.head / 'selected-evidence'
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(RemoteArchive()) as archive:
        entries = archive.namelist()
        manifest_path = next(name for name in entries if name.endswith('/manifest.json'))
        manifest = archive.read(manifest_path)
        (out / 'manifest.json').write_bytes(manifest)
        count = 0
        for group in json.loads(manifest):
            for attachment in group['attachments']:
                label = attachment['suggestedHumanReadableName']
                if not label.startswith('motionlab-') or not label.endswith('.png'):
                    continue
                filename = attachment['exportedFileName']
                source = next(name for name in entries if name.endswith('/' + filename))
                target = out / (label.split('_0_')[0] + '.png')
                if not target.exists():
                    target.write_bytes(archive.read(source))
                count += 1
        for filename in ['intro-to-home.mp4', 'poster-home.png']:
            source = next((name for name in entries if name.endswith('/' + filename)), None)
            if source is not None and not (out / filename).exists():
                (out / filename).write_bytes(archive.read(source))
    print(f'Collected {count} named native screenshots: {out}')


if __name__ == '__main__':
    main()
