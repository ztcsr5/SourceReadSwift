"""Collect screenshot evidence using bounded ZIP ranges, not XCTest's large videos.

Usage: python -X utf8 scripts/motion_lab_visual_evidence.py --head <SHA> --artifact <ID>
Reuses the existing GitHub transport; signed URLs and credentials are never logged.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import re
import random
import sys
import time
import urllib.error
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'docs/reader-recovery-119'))
import ci_status as github


def read_range(signed_url, start, end):
    request = urllib.request.Request(signed_url, headers={'Range': f'bytes={start}-{end}'})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                if response.status != 206:
                    raise RuntimeError('Artifact range ignored')
                content = response.read(end - start + 2)
                if len(content) > end - start + 1:
                    raise ValueError('Artifact response exceeded its requested range')
                return response.headers, content
        except urllib.error.HTTPError as error:
            if error.code not in (408, 429, 500, 502, 503, 504) or attempt == 3:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == 3:
                raise
        time.sleep(2 ** attempt + random.uniform(0, 0.3))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--head', required=True)
    parser.add_argument('--artifact', required=True, type=int)
    parser.add_argument('--entry', choices=['reader-startup.log', 'native-tab-test.log'])
    options = parser.parse_args()
    if not re.fullmatch('[a-f0-9]{40}', options.head):
        raise ValueError('Expected a full commit SHA')
    metadata = github.api(f'actions/artifacts/{options.artifact}')
    if options.entry == 'native-tab-test.log':
        matches = re.fullmatch(r'ios26-tab-evidence-' + options.head + r'-attempt[1-9][0-9]*', metadata['name']) is not None
    else:
        expected = ('ios-test-evidence-' if options.entry else 'motion-lab-evidence-') + options.head
        matches = metadata['name'] == expected
    if not matches:
        raise ValueError('Artifact does not match the requested tested head')
    url = f'https://api.github.com/repos/{github.REPO}/actions/artifacts/{options.artifact}/zip'
    try:
        urllib.request.build_opener(github.NoRedirect).open(urllib.request.Request(url, headers=github.HEADERS), timeout=30)
        raise RuntimeError('Expected a signed ZIP redirect')
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise RuntimeError(f'Artifact redirect failed: HTTP {error.code}') from None
        signed_url = error.headers['Location']
    headers, _ = read_range(signed_url, 0, 0)
    size = int(headers['Content-Range'].split('/')[-1])

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
            _, content = read_range(signed_url, self.position, end)
            self.position += len(content)
            return content

    out = Path('F:/SourceReadSwift/motion-lab') / options.head / 'selected-evidence'
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(RemoteArchive()) as archive:
        entries = archive.namelist()
        if options.entry:
            entry = next(name for name in entries if Path(name).name == options.entry)
            target = Path('F:/SourceReadSwift/reader-quality-137/verification') / options.head / options.entry
            target.parent.mkdir(parents=True, exist_ok=True)
            content = archive.read(entry)
            target.write_bytes(content)
            print(json.dumps({'path': str(target), 'bytes': len(content),
                              'sha256': hashlib.sha256(content).hexdigest()}))
            return
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
