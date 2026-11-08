"""Verify only continuous-scroll changes on the delivered source baseline.

Usage: python -B -X utf8 scripts/verify_scroll_quality.py snapshot|status
Uses a temporary index; preserves the user's dirty checkout and original index.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request

from verify_reader_quality import EVIDENCE, ROOT, github, read_status, run_git

BASE = '92c919b0a736f5d46b924f440e943bef1b7631d2'
RECEIPT = EVIDENCE / 'SCROLL-LATEST.json'
PATHS = [
    'SourceReadSwift/Features/Reader/WebScrollReaderView.swift',
    'SourceReadSwift/Features/Reader/WebReaderDocument.swift',
    'SourceReadSwift/Features/Reader/ReaderView.swift',
    'SourceReadSwift/Features/Reader/ReaderChapterWindow.swift',
    'SourceReadSwift/Features/Reader/ReaderWebPositionMapper.swift',
    'SourceReadSwiftTests/ReaderScrollSchedulingTests.swift',
    'SourceReadSwiftTests/ReaderScrollAnchorTests.swift',
    'scripts/test_reader_scroll_anchor.py',
    'scripts/verify_scroll_quality.py',
    '.github/workflows/reader-scroll.yml',
    'docs/project-audit-20261108/SCROLL-HITCH.md',
]


def dispatch(branch: str) -> None:
    request = urllib.request.Request(
        'https://api.github.com/repos/' + github.REPO + '/actions/workflows/ios.yml/dispatches',
        data=json.dumps({'ref': branch}).encode('utf8'), headers=github.HEADERS, method='POST')
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 204:
            raise RuntimeError(f'Scroll workflow dispatch expected 204; received {response.status}')


def snapshot() -> dict:
    if RECEIPT.exists():
        previous = json.loads(RECEIPT.read_text(encoding='utf8'))
        if any(run['status'] != 'completed' for run in read_status(previous)):
            raise RuntimeError('The previous scroll verification is still running; refusing overlap')
    with tempfile.TemporaryDirectory(prefix='reader-scroll-index-', dir=EVIDENCE) as temporary:
        environment = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / 'index'))
        run_git('read-tree', BASE, environment=environment)
        run_git('add', '--', *PATHS, environment=environment)
        template = (ROOT / '.github/workflows/reader-scroll.yml').read_bytes()
        workflow = subprocess.check_output(['git', 'hash-object', '-w', '--stdin'], cwd=ROOT, input=template).decode().strip()
        run_git('update-index', '--add', '--cacheinfo', '100644', workflow, '.github/workflows/ios.yml', environment=environment)
        tree = run_git('write-tree', environment=environment)
    stored = EVIDENCE / ('scroll-' + tree + '.json')
    if stored.exists():
        return json.loads(stored.read_text(encoding='utf8'))
    head = run_git('commit-tree', tree, '-p', BASE, '-m',
                   'fix(reader): preserve scroll inertia when chapters arrive')
    branch = 'codex/reader-quality-137-scroll-' + head[:12]
    run_git('push', 'origin', head + ':refs/heads/' + branch)
    record = {'head': head, 'tree': tree, 'parent': BASE, 'branch': branch,
              'paths': PATHS, 'purpose': 'Continuous scroll only; return gestures deferred by user',
              'dispatch_pending': True}
    for destination in [stored, RECEIPT]:
        destination.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf8')
    dispatch(branch)
    record['dispatch_pending'] = False
    for destination in [stored, RECEIPT]:
        destination.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf8')
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['snapshot', 'status'])
    action = parser.parse_args().action
    result = snapshot() if action == 'snapshot' else read_status(json.loads(RECEIPT.read_text(encoding='utf8')))
    print(json.dumps(result, ensure_ascii=False))
