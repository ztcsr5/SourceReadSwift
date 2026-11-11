"""Validate the current reader changes on iOS without triggering IPA packaging.

Usage: python -B -X utf8 scripts/verify_reader_quality.py snapshot|status [--base <COMMIT>]
Uses a temporary Git index; the checkout, user index and original dirty documents remain unchanged.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = Path("F:/SourceReadSwift/reader-quality-137/verification")
sys.path.insert(0, str(ROOT / "docs/reader-recovery-119"))


class GitHubTransport:
    """Load release credentials only when an actual GitHub operation needs them."""
    def __getattr__(self, name):
        import ci_status
        return getattr(ci_status, name)


github = GitHubTransport()


def run_git(*arguments, environment=None):
    outcome = subprocess.run(["git", *arguments], cwd=ROOT, env=environment, text=True,
                             encoding="utf8", capture_output=True, check=False)
    if outcome.returncode:
        message = re.sub(r"https?://[^\s]+", "[remote]", outcome.stderr)
        raise RuntimeError(f"Git {arguments[0]} failed: {message[:500]}")
    return outcome.stdout.strip()


def select_reader_paths(paths):
    build_inputs = (".swift", ".c", ".h", ".plist", ".entitlements", ".xcprivacy", ".ttf", ".otf",
                    ".json", ".html", ".txt", ".png", ".jpg", ".jpeg", ".svg", ".webp", ".pdf")
    return sorted({path for path in paths if
                   (path.endswith(build_inputs) and path.startswith(
                       ("SourceReadSwift/", "SourceReadSwiftTests/", "SourceReadSwiftUITests/")))
                   or (path.startswith("scripts/test_") and path.endswith(".py")) or path in
                   {".github/workflows/ios.yml", ".github/workflows/unsigned-ipa.yml", ".github/workflows/reader-diagnostics.yml", "project.yml", "SourceReadSwift/App/Info.plist",
                    "scripts/prepare_model_image.py", "scripts/boot_native_simulator.py",
                    "scripts/verify_reader_quality.py", "scripts/verify_reader_diagnostics.py",
                    "scripts/deliver_reader_quality.py",
                    "scripts/fixtures/ReaderZoomExperimentUITests.swift",
                    "scripts/verify_device_ipa.py", "scripts/generate_master_app_icon.py",
                    "scripts/watch_reader_build.py",
                    "docs/project-audit-20261108/REVIEW.md", "docs/project-audit-20261108/NAVIGATION.md",
                    "docs/project-audit-20261108/READER.md", "docs/project-audit-20261108/PARSERS.md",
                    "docs/project-audit-20261108/DESIGN.md", "docs/project-audit-20261108/ICON-REVIEW.png",
                    "CHANGELOG.md", "docs/sources/uxx-aggregate-compatible.json"}})


def dispatch_snapshot(record, record_path):
    """Persist the pushed identity before dispatch, including ambiguous network failures."""
    record["dispatch_pending"] = True
    persist_snapshot(record, record_path)
    request = urllib.request.Request(
        "https://api.github.com/repos/" + github.REPO + "/actions/workflows/ios.yml/dispatches",
        data=json.dumps({"ref": record["branch"]}).encode("utf8"), headers=github.HEADERS, method="POST")
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 204:
            raise RuntimeError(f"Workflow dispatch expected 204, got {response.status}")
    record["dispatch_pending"] = False
    persist_snapshot(record, record_path)
    return record


def persist_snapshot(record, record_path):
    contents = json.dumps(record, ensure_ascii=False, indent=2)
    record_path.write_text(contents, encoding="utf8")
    (record_path.parent / "LATEST.json").write_text(contents, encoding="utf8")


def snapshot_tree():
    """Project build inputs through a temporary index without touching the user's index."""
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    candidate_paths = run_git("diff", "--name-only", "HEAD").splitlines()
    candidate_paths += run_git("ls-files", "--others", "--exclude-standard",
                               "SourceReadSwift", "SourceReadSwiftTests", "SourceReadSwiftUITests",
                               ".github/workflows", "scripts", "docs/project-audit-20261108",
                               "docs/sources/uxx-aggregate-compatible.json").splitlines()
    selected = select_reader_paths(candidate_paths)
    if not selected:
        raise RuntimeError("No reader changes selected for native validation")
    with tempfile.TemporaryDirectory(prefix="reader-index-", dir=EVIDENCE) as temporary:
        environment = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / "index"))
        run_git("read-tree", "HEAD", environment=environment)
        run_git("add", "--", *selected, environment=environment)
        tree = run_git("write-tree", environment=environment)
    return tree, selected


def snapshot_changes(base=None):
    tree, selected = snapshot_tree()
    record_path = EVIDENCE / (tree + ".json")
    if record_path.exists():
        record = json.loads(record_path.read_text(encoding="utf8"))
        persist_snapshot(record, record_path)
        return record
    parent = run_git("rev-parse", "--verify", (base or "HEAD") + "^{commit}")
    commit = run_git("commit-tree", tree, "-p", parent, "-m",
                     "fix(reader): unify navigation and stabilize reading with atelier themes")
    branch = "codex/reader-quality-137-" + commit[:12]
    run_git("push", "origin", commit + ":refs/heads/" + branch)
    record = {"tree": tree, "head": commit, "parent": parent, "branch": branch, "paths": selected,
              "purpose": "iOS regression only; no IPA"}
    return dispatch_snapshot(record, record_path)


def read_status(record=None):
    record = record or json.loads((EVIDENCE / "LATEST.json").read_text(encoding="utf8"))
    runs = github.api("actions/runs?branch=" + record["branch"].replace("/", "%2F") + "&per_page=10")["workflow_runs"]
    selected = [run for run in runs if run["head_sha"] == record["head"] and run["path"] == ".github/workflows/ios.yml"]
    compact = []
    for run in selected:
        jobs = github.api(f"actions/runs/{run['id']}/jobs?per_page=50")["jobs"]
        for job in jobs:
            if job["status"] != "completed":
                continue
            log = EVIDENCE / f"job-{job['id']}.log"
            if not log.exists():
                try:
                    log.write_bytes(github.signed_download(f"actions/jobs/{job['id']}/logs"))
                except urllib.error.HTTPError as error:
                    if error.code != 404:
                        raise
                    job["evidence"] = {"pending": "Completed job log is not available yet"}
                    continue
            payload = log.read_bytes()
            failures = []
            for line in payload.decode("utf8", errors="replace").splitlines():
                if re.search(r"\.swift:\d+:\d+: error:|\.swift:\d+: error:|Test Case.*failed|\*\* (?:TEST(?: EXECUTE)?|BUILD) FAILED|Restarting after unexpected exit", line):
                    failures.append(re.sub(r"https?://[^\s]+", "[url]", line)[:600])
            job["evidence"] = {"bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest(),
                               "failures": failures[:8]}
        compact.append({key: run[key] for key in ["id", "status", "conclusion", "head_sha", "html_url"]} | {
            "jobs": [{"id": job["id"], "name": job["name"], "status": job["status"], "conclusion": job["conclusion"],
                      "step": next((step["name"] for step in job["steps"] if step["status"] == "in_progress"), None),
                      "evidence": job.get("evidence")}
                     for job in jobs]})
    (EVIDENCE / "STATUS.json").write_text(json.dumps(compact, ensure_ascii=False, indent=2), encoding="utf8")
    (EVIDENCE / (record["head"] + "-STATUS.json")).write_text(json.dumps(compact, ensure_ascii=False, indent=2), encoding="utf8")
    return compact


def download_visuals():
    record = json.loads((EVIDENCE / "LATEST.json").read_text(encoding="utf8"))
    runs = read_status()
    collector = EVIDENCE.parent / "collect.py"
    spec = importlib.util.spec_from_file_location("quality_evidence", collector)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    selected = []
    for run in runs:
        for artifact in github.api(f"actions/runs/{run['id']}/artifacts?per_page=50")["artifacts"]:
            if artifact["expired"] or record["head"] not in artifact["name"]:
                continue
            if not artifact["name"].startswith(("ios-ui-snapshots-", "ios26-ui-snapshots-")):
                continue
            selected.append(module.download_artifact(run, artifact, EVIDENCE))
    (EVIDENCE / "VISUALS.json").write_text(json.dumps(selected, ensure_ascii=False, indent=2), encoding="utf8")
    return selected


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["snapshot", "status", "visual"])
    parser.add_argument("--base", help="Preserved workspace baseline commit, keeping the new review independently revertible")
    arguments = parser.parse_args()
    actions = {"snapshot": lambda: snapshot_changes(arguments.base), "status": read_status, "visual": download_visuals}
    print(json.dumps(actions[arguments.action](), ensure_ascii=False))
