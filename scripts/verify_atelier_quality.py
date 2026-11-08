"""Freeze only theme changes on the green scroll/glass tree, preserving the dirty checkout.

Usage: python -B -X utf8 scripts/verify_atelier_quality.py tree|snapshot|status
The debug-only pending home-return probe is excluded from this theme snapshot.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request

from verify_reader_quality import EVIDENCE, ROOT, github, run_git

BASE = '9334c75b6ab067f86ceee5070a867daee820b95b'
RECEIPT = EVIDENCE / 'ATELIER-LATEST.json'
WORKFLOW = '.github/workflows/ios.yml'
TEMPLATE = '.github/workflows/atelier-redesign.yml'
PATHS = [
    'SourceReadSwift/Features/Bookshelf/AtelierReadingCard.swift',
    'SourceReadSwift/Features/Bookshelf/ThemedReadingCard.swift',
    'SourceReadSwift/Features/Bookshelf/BookshelfView.swift',
    'SourceReadSwift/Features/Settings/AppearanceSettingsView.swift',
    'SourceReadSwift/Shared/DesignSystem/AppAtelierTheme.swift',
    'SourceReadSwift/Shared/DesignSystem/AppThemeOrnament.swift',
    'SourceReadSwift/Shared/DesignSystem/AppThemeSurface.swift',
    'SourceReadSwift/Shared/DesignSystem/AppVisualTheme.swift',
    'SourceReadSwiftTests/AtelierThemeTests.swift',
    'SourceReadSwiftTests/AtelierLayoutTests.swift',
    'SourceReadSwiftUITests/AtelierHomeUITests.swift',
    'docs/project-audit-20261108/ATELIER-REDESIGN.md',
    'scripts/verify_atelier_quality.py', 'scripts/test_atelier_redesign.py', TEMPLATE,
]


def stage_text(relative: str, content: bytes, environment: dict) -> None:
    """Stage a bounded override without editing its checkout file."""
    blob = subprocess.check_output(['git', 'hash-object', '-w', '--stdin'], cwd=ROOT, input=content).decode().strip()
    run_git('update-index', '--add', '--cacheinfo', '100644', blob, relative, environment=environment)


def build_tree() -> dict:
    """Build a whitelisted tree using a disposable index, not the user's index."""
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='atelier-index-', dir=EVIDENCE) as folder:
        environment = dict(os.environ, GIT_INDEX_FILE=str(Path(folder) / 'index'))
        run_git('read-tree', BASE, environment=environment)
        run_git('add', '--', *PATHS, environment=environment)
        shelf = 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift'
        content = (ROOT / shelf).read_text(encoding='utf8')
        probe = '            #if DEBUG\n            .background(HomeReturnReadinessProbe())\n            #endif\n'
        if content.count(probe) > 1:
            raise ValueError('Expected at most one pending return-probe block')
        stage_text(shelf, content.replace(probe, '').encode('utf8'), environment)
        stage_text(WORKFLOW, (ROOT / TEMPLATE).read_bytes(), environment)
        tree = run_git('write-tree', environment=environment)
    changed = run_git('diff', '--name-only', BASE, tree).splitlines()
    if set(changed) - set(PATHS + [WORKFLOW]):
        raise ValueError('Snapshot includes paths outside the theme scope')
    return {'tree': tree, 'parent': BASE, 'paths': changed}


def persist(record: dict) -> None:
    payload = json.dumps(record, ensure_ascii=False, indent=2)
    for path in [RECEIPT, EVIDENCE / ('atelier-' + record['tree'] + '.json')]:
        path.write_text(payload, encoding='utf8')


def status() -> list[dict]:
    """Read only this frozen candidate; never dispatch while polling."""
    if not RECEIPT.exists():
        return []
    record = json.loads(RECEIPT.read_text(encoding='utf8'))
    branch = record['branch'].replace('/', '%2F')
    runs = github.api(f'actions/runs?branch={branch}&per_page=10')['workflow_runs']
    return [{key: run[key] for key in ['id', 'head_sha', 'status', 'conclusion', 'html_url']}
            for run in runs if run['head_sha'] == record['head'] and run['path'] == WORKFLOW]


def snapshot() -> dict:
    """Publish exactly one commit and dispatch a serial verification workflow."""
    if any(run['status'] != 'completed' for run in status()):
        raise ValueError('Previous theme workflow is still running')
    frozen = build_tree()
    saved = EVIDENCE / ('atelier-' + frozen['tree'] + '.json')
    if saved.exists():
        record = json.loads(saved.read_text(encoding='utf8'))
        persist(record)
        return record
    head = run_git('commit-tree', frozen['tree'], '-p', BASE, '-m',
                   'feat(appearance): redesign atelier homes with quiet split layouts')
    branch = 'codex/reader-quality-137-atelier-' + head[:12]
    run_git('push', 'origin', head + ':refs/heads/' + branch)
    record = frozen | {'head': head, 'branch': branch, 'workflow': WORKFLOW, 'dispatch_pending': True}
    persist(record)
    request = urllib.request.Request('https://api.github.com/repos/' + github.REPO
        + '/actions/workflows/ios.yml/dispatches', data=json.dumps({'ref': branch}).encode('utf8'),
        headers=github.HEADERS, method='POST')
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 204:
            raise RuntimeError(f'Theme dispatch expected HTTP 204; got {response.status}')
    record['dispatch_pending'] = False
    persist(record)
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['tree', 'snapshot', 'status'])
    options = parser.parse_args()
    print(json.dumps({'tree': build_tree, 'snapshot': snapshot, 'status': status}[options.action](), ensure_ascii=False))
