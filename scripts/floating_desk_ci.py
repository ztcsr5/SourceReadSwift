"""Save exact-head floating-desk CI and compact runtime evidence, never an IPA.

Usage: python -X utf8 scripts/floating_desk_ci.py [--watch] [--download]
Uses the existing credential-safe GitHub transport; no signed URL is printed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
import zipfile

from reader_motion_ci import github, save_job_log


def download_evidence(run, destination):
    artifacts = github.api(f"actions/runs/{run['id']}/artifacts")['artifacts']
    for artifact in artifacts:
        name = artifact['name']
        if not name.startswith('floating-desk-') or name.startswith('floating-desk-xcresult-'):
            continue
        if artifact['size_in_bytes'] > 512 * 1024 * 1024:
            raise ValueError('Compact evidence unexpectedly exceeds 512 MB; inspect its manifest first')
        archive = destination / (str(artifact['id']) + '.zip')
        if not archive.exists():
            archive.write_bytes(github.signed_download(f"actions/artifacts/{artifact['id']}/zip"))
        target = destination / name
        with zipfile.ZipFile(archive) as package:
            if package.testzip() is not None:
                raise ValueError('Floating-desk evidence ZIP failed CRC validation')
            for entry in package.infolist():
                path = (target / entry.filename).resolve()
                if not path.is_relative_to(target.resolve()):
                    raise ValueError('Evidence path escaped its destination')
                if not entry.is_dir():
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(package.read(entry))
        print('EVIDENCE', name, archive.stat().st_size, hashlib.sha256(archive.read_bytes()).hexdigest(), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--download', action='store_true')
    options = parser.parse_args()
    destination = Path('F:/SourceReadSwift/floating-desk-117') / github.HEAD
    destination.mkdir(parents=True, exist_ok=True)
    previous = None
    for _ in range(240 if options.watch else 1):
        runs = github.api('actions/runs?branch=codex%2Ffloating-reading-desk&per_page=20')['workflow_runs']
        records = []
        for run in runs:
            if run['head_sha'] != github.HEAD or run['name'] != 'Floating Reading Desk':
                continue
            jobs = github.api(f"actions/runs/{run['id']}/jobs")['jobs']
            record = {key: run.get(key) for key in ['id', 'head_sha', 'status', 'conclusion', 'html_url']}
            records.append(record | {'jobs': jobs})
            for job in jobs:
                save_job_log(job, destination)
            if options.download:
                download_evidence(run, destination)
        signature = [(run['id'], run['status'], run['conclusion'], [(job['id'], job['status'], job['conclusion'],
            [step['name'] for step in job.get('steps', []) if step['status'] == 'in_progress']) for job in run['jobs']]) for run in records]
        if signature != previous:
            print(json.dumps(signature, ensure_ascii=False), flush=True)
            previous = signature
        (destination / 'ci-status.json').write_text(json.dumps({'head': github.HEAD, 'runs': records,
            'scope': 'experimental floating reading desk; no IPA; simulator results are not device FPS'}, ensure_ascii=False, indent=2), encoding='utf8')
        if not options.watch or (records and all(run['status'] == 'completed' for run in records)):
            break
        time.sleep(30)


if __name__ == '__main__':
    main()
