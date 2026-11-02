"""Preserve exact-head 1.1.7 motion CI evidence without exposing credentials.

Usage: python -X utf8 scripts/reader_motion_ci.py [--watch] [--download ipa|previews]
Reuses the repository's existing read-only GitHub transport. No provider calls.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys
import time
import zipfile
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'docs/reader-recovery-119'))
import ci_status as github


def read_runs():
    runs = github.api('actions/runs?branch=codex%2Freader-motion-117&per_page=12')['workflow_runs']
    return [run for run in runs if run['head_sha'] == github.HEAD]


def save_job_log(job, destination):
    if job['status'] != 'completed':
        return
    path = destination / f"job-{job['id']}.log"
    if path.exists():
        return
    try:
        contents = github.signed_download(f"actions/jobs/{job['id']}/logs")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            print('LOG_PENDING', job['id'], 'completed-job blob is not available yet', flush=True)
            return
        raise RuntimeError(f"Unable to preserve job {job['id']} log: HTTP {error.code}") from error
    path.write_bytes(contents)
    print('LOG', path.name, path.stat().st_size, hashlib.sha256(path.read_bytes()).hexdigest(), flush=True)
    lines = path.read_text(encoding='utf8', errors='replace').splitlines()
    errors = [line for line in lines if re.search(r'error:|Test Case.*failed|Executed \d+ tests, with [1-9]', line)]
    outcomes = [line for line in lines if re.search(r'Executed \d+ tests|\*\* (TEST|BUILD)', line)]
    for line in errors[:3] + outcomes[-3:]:
        print(line[:500], flush=True)


def download_artifacts(runs, kind, destination):
    for run in runs:
        if kind == 'ipa' and (run['name'] != 'Unsigned IPA' or run['conclusion'] != 'success'):
            continue
        for artifact in github.api(f"actions/runs/{run['id']}/artifacts")['artifacts']:
            name = artifact['name']
            if kind == 'ipa' and name != 'SourceReadSwift-unsigned-ipa':
                continue
            if kind == 'previews' and not name.startswith('ios26-ui-snapshots-'):
                continue
            if artifact['size_in_bytes'] > 100 * 1024 * 1024:
                raise ValueError('Refusing an unexpectedly large artifact; use a bounded evidence selection')
            archive = destination / (name + '.zip')
            if not archive.exists():
                archive.write_bytes(github.signed_download(f"actions/artifacts/{artifact['id']}/zip"))
            target = destination / name
            with zipfile.ZipFile(archive) as package:
                if package.testzip() is not None:
                    raise ValueError('Artifact ZIP CRC failed')
                for entry in package.infolist():
                    path = (target / entry.filename).resolve()
                    if not path.is_relative_to(target.resolve()):
                        raise ValueError('Artifact path escaped its destination')
                    if not entry.is_dir():
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_bytes(package.read(entry))
            print('ARTIFACT', archive, archive.stat().st_size, hashlib.sha256(archive.read_bytes()).hexdigest(), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--download', choices=['ipa', 'previews'])
    options = parser.parse_args()
    destination = Path('F:/SourceReadSwift/reader-motion-117') / github.HEAD
    destination.mkdir(parents=True, exist_ok=True)
    previous = None
    for _ in range(40 if options.watch else 1):
        runs = read_runs()
        records = []
        for run in runs:
            jobs = github.api(f"actions/runs/{run['id']}/jobs")['jobs']
            records.append({key: run.get(key) for key in ['id', 'name', 'head_sha', 'status', 'conclusion', 'html_url']} | {'jobs': jobs})
            for job in jobs:
                save_job_log(job, destination)
        signature = [(run['id'], run['status'], run['conclusion'], [(job['id'], job['status'], job['conclusion'], [step['name'] for step in job['steps'] if step['status'] == 'in_progress']) for job in run['jobs']]) for run in records]
        if signature != previous:
            print(json.dumps(signature, ensure_ascii=False), flush=True)
            previous = signature
        (destination / 'ci-status.json').write_text(json.dumps({'head': github.HEAD, 'runs': records}, ensure_ascii=False, indent=2), encoding='utf8')
        if not options.watch or (runs and all(run['status'] == 'completed' for run in runs)):
            break
        time.sleep(30)
    if options.download:
        download_artifacts(runs, options.download, destination)


if __name__ == '__main__':
    main()
