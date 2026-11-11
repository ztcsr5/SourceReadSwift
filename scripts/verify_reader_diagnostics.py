"""Run only the concrete reader failures; diagnostic success never authorizes IPA delivery.

Usage: python -B -X utf8 scripts/verify_reader_diagnostics.py snapshot|status
Keeps a separate identity from complete validation; never modifies the user index.
"""
import argparse
import hashlib
import io
import json
import os
import subprocess
import tempfile
from pathlib import Path
import re
import urllib.request
import zipfile

import verify_reader_quality as quality

WORKFLOW = ".github/workflows/ios.yml"
TEMPLATE = ".github/workflows/reader-diagnostics.yml"
LATEST = quality.EVIDENCE / "DIAGNOSTICS-LATEST.json"


def persist_diagnostic(record: dict, path: Path) -> None:
    """Save identity before a possibly ambiguous dispatch response."""
    payload = json.dumps(record, ensure_ascii=False, indent=2)
    path.write_text(payload, encoding="utf8")
    LATEST.write_text(payload, encoding="utf8")


def failure_lines(payload: bytes) -> list[str]:
    """Keep exact assertion/build failures without printing a multi-megabyte log."""
    lines = payload.decode("utf8", errors="replace").splitlines()
    return [re.sub(r"https?://[^\s]+", "[url]", line)[:700] for line in lines
            if re.search(r"\.swift:\d+(?::\d+)?: error:|Test Case.*failed|\*\* (?:TEST(?: EXECUTE)?|BUILD) FAILED|Restarting after unexpected exit", line)]


def collect_early_unit(run_id: int, record: dict) -> dict | None:
    """Read the iOS26 early log; artifact upload order must not select another runtime."""
    folder = quality.EVIDENCE / record["head"] / "diagnostics"
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / "diagnostic-unit-ios26.log"
    if not target.exists():
        artifacts = quality.github.api(f"actions/runs/{run_id}/artifacts?per_page=50")["artifacts"]
        artifact = next((row for row in artifacts if not row["expired"]
                         and row["name"].startswith("reader-diag-unit-" + record["head"] + "-ios26-")), None)
        if artifact is None:
            return None
        archive_bytes = quality.github.signed_download(f"actions/artifacts/{artifact['id']}/zip")
        with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
            member = next(row for row in archive.infolist() if row.filename.endswith("diagnostic-unit.log"))
            if member.file_size > 4 * 1024 * 1024:
                raise RuntimeError("Diagnostic unit log exceeds 4 MiB bounded read")
            target.write_bytes(archive.read(member))
    payload = target.read_bytes()
    return {"runtime": "26", "path": str(target), "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest(),
            "failures": failure_lines(payload)}


def read_diagnostics_status(record: dict | None = None) -> list[dict]:
    """Query only this focused snapshot, not a release workflow or an older SHA."""
    if record is None:
        if not LATEST.exists():
            return []
        record = json.loads(LATEST.read_text(encoding="utf8"))
    branch = record["branch"].replace("/", "%2F")
    runs = quality.github.api("actions/runs?branch=" + branch + "&per_page=10")["workflow_runs"]
    selected = [run for run in runs if run["head_sha"] == record["head"] and run["path"] == WORKFLOW]
    result = []
    for run in selected:
        jobs = quality.github.api(f"actions/runs/{run['id']}/jobs?per_page=50")["jobs"]
        compact = []
        for job in jobs:
            evidence = None
            if job["status"] == "completed":
                log = quality.EVIDENCE / ("diagnostic-job-" + str(job["id"]) + ".log")
                if not log.exists():
                    log.write_bytes(quality.github.signed_download(f"actions/jobs/{job['id']}/logs"))
                payload = log.read_bytes()
                evidence = {"path": str(log), "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest(),
                            "failures": failure_lines(payload)}
            compact.append({"id": job["id"], "status": job["status"], "conclusion": job["conclusion"],
                            "step": next((step["name"] for step in job["steps"] if step["status"] == "in_progress"), None),
                            "evidence": evidence})
        result.append({"id": run["id"], "status": run["status"], "conclusion": run["conclusion"],
                       "head_sha": run["head_sha"], "html_url": run["html_url"], "jobs": compact,
                       "early_unit": collect_early_unit(run["id"], record)})
    (quality.EVIDENCE / "DIAGNOSTICS-STATUS.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf8")
    return result


def materialize_focused_tree(tree: str) -> str:
    """Override only the diagnostic commit's registered entry, never the user's full workflow."""
    with tempfile.TemporaryDirectory(prefix="reader-diag-index-", dir=quality.EVIDENCE) as temporary:
        environment = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / "index"))
        quality.run_git("read-tree", tree, environment=environment)
        payload = (quality.ROOT / TEMPLATE).read_bytes()
        blob = subprocess.check_output(["git", "hash-object", "-w", "--stdin"], cwd=quality.ROOT, input=payload).decode().strip()
        quality.run_git("update-index", "--add", "--cacheinfo", "100644", blob, WORKFLOW, environment=environment)
        return quality.run_git("write-tree", environment=environment)


def snapshot_diagnostics(*, ios26_only: bool = False, zoom_experiment: bool = False) -> dict:
    """Push one complete source tree but dispatch only the focused diagnostic job."""
    full_latest = quality.EVIDENCE / "LATEST.json"
    if full_latest.exists() and any(run["status"] != "completed" for run in quality.read_status()):
        raise RuntimeError("Complete validation is still running; refusing overlapping diagnostics")
    if any(run["status"] != "completed" for run in read_diagnostics_status()):
        raise RuntimeError("Reader diagnostics are still running; refusing overlap")
    tree, selected = quality.snapshot_tree()
    if TEMPLATE not in selected:
        raise RuntimeError("Focused workflow was omitted from snapshot inputs")
    tree = materialize_focused_tree(tree)
    runtime_suffix = "-ios26" if ios26_only else ""
    if zoom_experiment:
        runtime_suffix += "-zoom-experiment"
    receipt = quality.EVIDENCE / ("diagnostic-" + tree + runtime_suffix + ".json")
    if receipt.exists():
        record = json.loads(receipt.read_text(encoding="utf8"))
        persist_diagnostic(record, receipt)
        return record
    head = quality.run_git("commit-tree", tree, "-p", quality.run_git("rev-parse", "HEAD"), "-m",
                           "test(reader): isolate iOS 26 edge input" if ios26_only
                           else "test(reader): isolate held HTTP focus and return failures")
    branch = "codex/reader-quality-137-diag-" + head[:12]
    quality.run_git("push", "origin", head + ":refs/heads/" + branch)
    record = {"head": head, "tree": tree, "branch": branch, "workflow": WORKFLOW, "template": TEMPLATE, "paths": selected,
              "purpose": "Focused diagnostics only; never an IPA gate", "ios26_only": ios26_only,
              "zoom_experiment": zoom_experiment, "dispatch_pending": True}
    persist_diagnostic(record, receipt)
    request = urllib.request.Request("https://api.github.com/repos/" + quality.github.REPO
                                     + "/actions/workflows/ios.yml/dispatches",
                                     data=json.dumps({"ref": branch, "inputs": {"ios26_only": ios26_only,
                                                                               "zoom_experiment": zoom_experiment}}).encode("utf8"),
                                     headers=quality.github.HEADERS, method="POST")
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 204:
            raise RuntimeError("Diagnostic dispatch did not return 204")
    record["dispatch_pending"] = False
    persist_diagnostic(record, receipt)
    return record


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["snapshot", "status"])
    parser.add_argument("--ios26-only", action="store_true", help="Run only the iOS 26 diagnostic job")
    parser.add_argument("--zoom-experiment", action="store_true", help="Run controlled Zoom and viewport experiments only")
    args = parser.parse_args()
    if (args.ios26_only or args.zoom_experiment) and args.action != "snapshot":
        parser.error("Experiment/runtime flags require snapshot")
    output = snapshot_diagnostics(ios26_only=args.ios26_only, zoom_experiment=args.zoom_experiment) if args.action == "snapshot" else read_diagnostics_status()
    if isinstance(output, dict):
        output = {key: output[key] for key in ["head", "tree", "branch", "purpose", "dispatch_pending"]}
    print(json.dumps(output, ensure_ascii=False))
