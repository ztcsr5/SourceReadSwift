"""Snapshot and verify root-tab glass without touching the dirty checkout or user index.

Usage: python -B -X utf8 scripts/verify_tab_glass_quality.py tree|snapshot|status
The registered workflow entry is replaced only inside the temporary Git tree.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.request

from verify_reader_quality import EVIDENCE, ROOT, github, run_git


BASE = "565a44ecd93982f9d6293d6da29729155862b817"
RECEIPT = EVIDENCE / "TAB-GLASS-LATEST.json"
WORKFLOW = ".github/workflows/ios.yml"
TEMPLATE = ".github/workflows/tab-glass.yml"
PATHS = [
    "SourceReadSwift/Shared/DesignSystem/LegacyTabBar.swift",
    "SourceReadSwift/Shared/DesignSystem/RootTabGlassSurface.swift",
    "SourceReadSwiftTests/RootTabGlassTests.swift",
    "SourceReadSwiftUITests/RootTabGlassUITests.swift",
    "scripts/verify_tab_glass_quality.py",
    "scripts/test_tab_glass_workflow.py",
    TEMPLATE,
    "docs/project-audit-20261108/TAB-GLASS.md",
]


def build_tree() -> dict:
    """Freeze only tab inputs on the successful scroll baseline."""
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="tab-glass-index-", dir=EVIDENCE) as temporary:
        environment = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / "index"))
        run_git("read-tree", BASE, environment=environment)
        run_git("add", "--", *PATHS, environment=environment)
        template = (ROOT / TEMPLATE).read_bytes()
        blob = subprocess.check_output(["git", "hash-object", "-w", "--stdin"],
                                       cwd=ROOT, input=template).decode().strip()
        run_git("update-index", "--add", "--cacheinfo", "100644", blob, WORKFLOW, environment=environment)
        tree = run_git("write-tree", environment=environment)
    changed = run_git("diff", "--name-only", BASE, tree).splitlines()
    if set(changed) - set(PATHS + [WORKFLOW]):
        raise RuntimeError("Tab-glass snapshot includes an unauthorized path")
    return {"tree": tree, "parent": BASE, "paths": changed}


def persist(record: dict) -> None:
    payload = json.dumps(record, ensure_ascii=False, indent=2)
    for destination in [RECEIPT, EVIDENCE / ("tab-glass-" + record["tree"] + ".json")]:
        destination.write_text(payload, encoding="utf8")


def status(record: dict | None = None) -> list[dict]:
    """Read this snapshot only and keep logs separate from the scroll evidence."""
    if record is None:
        if not RECEIPT.exists():
            return []
        record = json.loads(RECEIPT.read_text(encoding="utf8"))
    branch = record["branch"].replace("/", "%2F")
    runs = github.api("actions/runs?branch=" + branch + "&per_page=10")["workflow_runs"]
    selected = [run for run in runs if run["head_sha"] == record["head"] and run["path"] == WORKFLOW]
    result = []
    for run in selected:
        compact = []
        for job in github.api(f"actions/runs/{run['id']}/jobs?per_page=50")["jobs"]:
            evidence = None
            if job["status"] == "completed":
                target = EVIDENCE / ("tab-glass-job-" + str(job["id"]) + ".log")
                if not target.exists():
                    try:
                        target.write_bytes(github.signed_download(f"actions/jobs/{job['id']}/logs"))
                    except urllib.error.HTTPError as error:
                        if error.code != 404:
                            raise
                if target.exists():
                    payload = target.read_bytes()
                    failures = [re.sub(r"https?://[^\s]+", "[url]", line)[:700]
                                for line in payload.decode("utf8", errors="replace").splitlines()
                                if re.search(r"\.swift:\d+(?::\d+)?: error:|Test Case.*failed|\*\* (?:TEST(?: EXECUTE)?|BUILD) FAILED", line)]
                    evidence = {"path": str(target), "bytes": len(payload),
                                "sha256": hashlib.sha256(payload).hexdigest(), "failures": failures}
            compact.append({"id": job["id"], "name": job["name"], "status": job["status"],
                            "conclusion": job["conclusion"], "evidence": evidence,
                            "step": next((step["name"] for step in job["steps"] if step["status"] == "in_progress"), None)})
        result.append({key: run[key] for key in ["id", "head_sha", "status", "conclusion", "html_url"]} | {"jobs": compact})
    (EVIDENCE / "TAB-GLASS-STATUS.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf8")
    return result


def snapshot() -> dict:
    """Push and dispatch once; save identity before an ambiguous dispatch response."""
    if any(run["status"] != "completed" for run in status()):
        raise RuntimeError("Previous tab-glass verification is still running; refusing overlap")
    tree = build_tree()
    stored = EVIDENCE / ("tab-glass-" + tree["tree"] + ".json")
    if stored.exists():
        record = json.loads(stored.read_text(encoding="utf8"))
        persist(record)
        return record
    head = run_git("commit-tree", tree["tree"], "-p", BASE, "-m", "fix(navigation): restore translucent root tabs and search")
    branch = "codex/reader-quality-137-tab-glass-" + head[:12]
    run_git("push", "origin", head + ":refs/heads/" + branch)
    record = tree | {"head": head, "branch": branch, "workflow": WORKFLOW,
                     "purpose": "Root-tab glass and home search only; no IPA", "dispatch_pending": True}
    persist(record)
    request = urllib.request.Request("https://api.github.com/repos/" + github.REPO
        + "/actions/workflows/ios.yml/dispatches", data=json.dumps({"ref": branch}).encode("utf8"),
        headers=github.HEADERS, method="POST")
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 204:
            raise RuntimeError(f"Tab-glass dispatch expected 204; received {response.status}")
    record["dispatch_pending"] = False
    persist(record)
    return record


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["tree", "snapshot", "status"])
    action = parser.parse_args().action
    print(json.dumps({"tree": build_tree, "snapshot": snapshot, "status": status}[action](), ensure_ascii=False))
