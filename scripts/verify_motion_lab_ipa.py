"""Verify and copy a CI-produced independent IPA without replacing other builds.

Usage: python -X utf8 scripts/verify_motion_lab_ipa.py --head <TESTED_SHA> --build 2
No signing credentials are read. Output is an unsigned sideloading candidate.
"""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import struct
import zipfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--head', required=True)
    parser.add_argument('--build', required=True)
    options = parser.parse_args()
    if len(options.head) != 40 or any(c not in '0123456789abcdef' for c in options.head):
        raise ValueError('Expected the full lowercase 40-character tested commit')
    root = Path('F:/SourceReadSwift/motion-lab') / options.head
    status = json.loads((root / 'ci-status.json').read_text(encoding='utf8'))
    successes = [run for run in status['runs'] if run['head_sha'] == options.head and run['conclusion'] == 'success']
    if not successes:
        raise ValueError('No successful exact-head Motion Lab workflow; refusing delivery')
    candidates = list((root / ('motion-lab-ipa-' + options.head)).glob('*.ipa'))
    if len(candidates) != 1:
        raise ValueError(f'Expected one downloaded test IPA, found {len(candidates)}')
    package = candidates[0]
    with zipfile.ZipFile(package) as archive:
        if archive.testzip() is not None:
            raise ValueError('IPA CRC validation failed')
        names = archive.namelist()
        manifests = [name for name in names if name.startswith('Payload/') and name.endswith('.app/Info.plist') and name.count('/') == 2]
        if len(manifests) != 1:
            raise ValueError('IPA does not contain exactly one top-level app')
        manifest = manifests[0]
        bundle = plistlib.loads(archive.read(manifest))
        expected = {'CFBundleIdentifier': 'com.edc21.ZhijianMotionLab', 'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': options.build, 'MinimumOSVersion': '16.0'}
        for key, value in expected.items():
            if str(bundle.get(key)) != value:
                raise ValueError(f'IPA {key}: expected {value}, received {bundle.get(key)}')
        executable = manifest.removesuffix('Info.plist') + bundle['CFBundleExecutable']
        magic, architecture = struct.unpack('<II', archive.read(executable)[:8])
        if magic != 0xFEEDFACF or architecture != 0x0100000C:
            raise ValueError('IPA executable is not a thin 64-bit ARM device Mach-O')
        if bundle.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
            raise ValueError('IPA is not a real iPhoneOS build')
        if any(name.endswith('embedded.mobileprovision') for name in names):
            raise ValueError('Expected an unsigned candidate without an embedded signing profile')
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    desktop = Path.home() / 'Desktop' / f'ZhijianMotionLab-0.1.0-build{options.build}-{options.head[:7]}-unsigned.ipa'
    if desktop.exists() and hashlib.sha256(desktop.read_bytes()).hexdigest() != digest:
        raise FileExistsError('Existing desktop IPA has different bytes; refusing to overwrite')
    if not desktop.exists():
        shutil.copy2(package, desktop)
    report = {'tested_head': options.head, 'workflow': successes[0]['html_url'], 'source': str(package), 'desktop': str(desktop), 'bytes': package.stat().st_size, 'sha256': digest, 'expected_bundle': expected, 'architecture': 'arm64', 'zip_crc': 'pass', 'platform': 'iPhoneOS', 'signing': 'unsigned; user signing required'}
    (root / 'IPA_VERIFICATION.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
