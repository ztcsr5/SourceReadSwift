"""Deliver a user-authorized device test build without claiming UI acceptance.

Usage: python -B -X utf8 scripts/deliver_manual_test_ipa.py <COMMIT> <PACKAGE_RUN>
Requires the explicit per-commit MANUAL_TEST_PACKAGE_AUTHORIZATION.json receipt.
Preserves the separate full-regression delivery gate and downloads serially.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import plistlib
import sys
import zipfile

from deliver_reader_quality import package_filename, publish_verified_ipa
from verify_device_ipa import verify_device_ipa
from verify_reader_quality import EVIDENCE, github, run_git

sys.path.insert(0, str(EVIDENCE.parent))
from select_visual import ReadOnlyRange, location


def read_artifact(artifact: dict, folder: Path, suffix: str) -> bytes:
    """Download one bounded artifact sequentially and verify its ZIP entries."""
    size = artifact['size_in_bytes']
    if artifact['expired'] or not 0 < size < 100 * 1024 * 1024:
        raise ValueError('Expected a live artifact smaller than 100 MiB')
    archive = folder / f"artifact-{artifact['id']}.zip"
    if not archive.exists():
        reader = ReadOnlyRange(location(artifact), size)
        staged = archive.with_suffix('.part')
        with staged.open('wb') as output:
            while reader.tell() < size:
                output.write(reader.read(min(3 * 1024 * 1024, size-reader.tell())))
                print(json.dumps({'artifact': artifact['id'], 'received': reader.tell(), 'total': size}), flush=True)
        with zipfile.ZipFile(staged) as package:
            if package.testzip() is not None:
                raise ValueError('Downloaded artifact failed ZIP integrity verification')
        staged.replace(archive)
    with zipfile.ZipFile(archive) as package:
        if package.testzip() is not None:
            raise ValueError('Cached artifact failed ZIP integrity verification')
        names = [n for n in package.namelist() if n.endswith(suffix)]
        if len(names) != 1:
            raise ValueError(f'Expected one {suffix} payload, found {len(names)}')
        return package.read(names[0])


def deliver_test_build(head: str, run_id: int) -> dict:
    """Verify the selected Release IPA and publish it with honest test status."""
    head = run_git('rev-parse', '--verify', head+'^{commit}')
    folder = EVIDENCE / head
    authorization = json.loads((folder/'MANUAL_TEST_PACKAGE_AUTHORIZATION.json').read_text(encoding='utf8'))
    if authorization.get('head') != head or authorization.get('dispatch_requested') is not True:
        raise ValueError('Missing authorization for this exact manual-test build')
    run = github.api(f'actions/runs/{run_id}')
    if run['head_sha'] != head or run['path'] != '.github/workflows/unsigned-ipa.yml' or run['conclusion'] != 'success':
        raise ValueError('Expected a successful unsigned device workflow for the selected commit')
    jobs = github.api(f'actions/runs/{run_id}/jobs?per_page=50')['jobs']
    if not any(j['name'] == 'package' and j['conclusion'] == 'success' for j in jobs):
        raise ValueError('Device package job did not succeed')
    artifacts = github.api(f'actions/runs/{run_id}/artifacts?per_page=50')['artifacts']
    ipa = read_artifact(next(a for a in artifacts if a['name'] == 'SourceReadSwift-unsigned-ipa'), folder, '.ipa')
    symbols = read_artifact(next(a for a in artifacts if a['name'] == 'SourceReadSwift-device-symbols-'+head), folder, '.zip')
    verified = verify_device_ipa(ipa, symbols, run_git('show', head+':project.yml'), folder)
    with zipfile.ZipFile(io.BytesIO(ipa)) as package:
        plist = plistlib.loads(package.read('Payload/SourceReadSwift.app/Info.plist'))
        comic_type = 'com.edc21.sourceread.cbz'
        if not any(c.get('UTTypeIdentifier') == comic_type for c in plist.get('UTImportedTypeDeclarations', [])):
            raise ValueError('Device package is missing the CBZ UTI')
        if not any(comic_type in c.get('LSItemContentTypes', []) for c in plist.get('CFBundleDocumentTypes', [])):
            raise ValueError('Device package is missing the CBZ document registration')
        icons = [n for n in package.namelist() if '/AppIcon' in n and n.endswith('.png')]
        for name in icons:
            (folder/Path(name).name).write_bytes(package.read(name))
    fingerprint = hashlib.sha256(ipa).hexdigest()
    filename = package_filename(plist, head)
    output = folder/filename
    if output.exists() and output.read_bytes() != ipa:
        raise ValueError('Refusing to overwrite a different device package')
    if not output.exists():
        output.write_bytes(ipa)
    desktop = Path.home()/'Desktop'/filename
    publish_verified_ipa(output, desktop, fingerprint)
    receipt = verified | {'head': head, 'package_run': run_id, 'package_url': run['html_url'],
        'sha256': fingerprint, 'bytes': len(ipa), 'desktop_ipa': str(desktop),
        'full_ui_regression_passed': False, 'acceptance': 'manual testing delegated by user',
        'unsigned': True, 'device_installed': False, 'cbz_registered': True,
        'extracted_icons': [str(folder/Path(n).name) for n in icons]}
    (folder/'IPA_VERIFICATION_MANUAL_TEST.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf8')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('head')
    parser.add_argument('run', type=int)
    arguments = parser.parse_args()
    print(json.dumps(deliver_test_build(arguments.head, arguments.run), ensure_ascii=False))
