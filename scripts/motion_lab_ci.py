"""Inspect exact-head Motion Lab CI and preserve logs, without printing credentials.

Usage: python -X utf8 scripts/motion_lab_ci.py [--download]
Reuses this repository's existing authenticated read-only GitHub transport.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'docs/reader-recovery-119'))
import ci_status as github


def main() -> None:
    """Read only this branch/head's independent workflow and optionally collect artifacts."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    options = parser.parse_args()
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    out = Path('F:/SourceReadSwift/motion-lab') / head
    out.mkdir(parents=True, exist_ok=True)
    runs = github.api('actions/runs?branch=codex%2Fmotion-lab&per_page=20')['workflow_runs']
    statuses = []
    for run in runs:
        if run['head_sha'] != head or run['name'] != 'Motion Lab':
            continue
        jobs = github.api(f"actions/runs/{run['id']}/jobs")['jobs']
        status = {key: run.get(key) for key in ['id', 'name', 'head_sha', 'status', 'conclusion', 'html_url']}
        status['jobs'] = jobs
        statuses.append(status)
        print(run['id'], run['status'], run['conclusion'], flush=True)
        for job in jobs:
            print(job['id'], [(s['name'], s['conclusion']) for s in job['steps'] if s['conclusion'] not in ['success', 'skipped']], flush=True)
            if job['status'] == 'completed':
                log = out / f"job-{job['id']}.log"
                if not log.exists():
                    log.write_bytes(github.signed_download(f"actions/jobs/{job['id']}/logs"))
        if options.download:
            artifacts = github.api(f"actions/runs/{run['id']}/artifacts")['artifacts']
            for artifact in artifacts:
                if not artifact['name'].startswith('motion-lab-') or artifact.get('expired'):
                    continue
                archive = out / (artifact['name'] + '.zip')
                if not archive.exists():
                    print('DOWNLOAD', artifact['name'], artifact['size_in_bytes'], flush=True)
                    archive.write_bytes(github.signed_download(f"actions/artifacts/{artifact['id']}/zip"))
                destination = out / artifact['name']
                destination.mkdir(exist_ok=True)
                with zipfile.ZipFile(io.BytesIO(archive.read_bytes())) as package:
                    if package.testzip() is not None:
                        raise ValueError('Motion Lab artifact failed ZIP CRC')
                    for entry in package.infolist():
                        target = (destination / entry.filename).resolve()
                        if not target.is_relative_to(destination.resolve()):
                            raise ValueError('Motion Lab artifact path escaped destination')
                        if entry.is_dir():
                            continue
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(package.read(entry))
                print('SAVED', archive.name, 'SHA256', hashlib.sha256(archive.read_bytes()).hexdigest(), flush=True)
    (out / 'ci-status.json').write_text(json.dumps({'head': head, 'runs': statuses}, ensure_ascii=False, indent=2), encoding='utf8')


if __name__ == '__main__':
    main()
