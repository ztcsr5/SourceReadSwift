"""Follow one submitted GitHub build in this session, printing only state changes.

Usage: python -B -X utf8 scripts/watch_reader_build.py [--package-run <ID>]
Does not dispatch, rerun, create automations, or modify source code.
"""
import argparse
from datetime import datetime, timezone
import json
import time
import urllib.error

from verify_reader_quality import EVIDENCE, github, read_status


def package_status(run_id: int) -> list:
    """Fetch compact status for an already-dispatched package run."""
    run = github.api(f"actions/runs/{run_id}")
    jobs = github.api(f"actions/runs/{run_id}/jobs?per_page=50")["jobs"]
    return [{key: run[key] for key in ["id", "status", "conclusion", "head_sha", "html_url"]} | {
        "jobs": [{"id": job["id"], "name": job["name"], "status": job["status"],
                  "conclusion": job["conclusion"],
                  "step": next((step["name"] for step in job["steps"] if step["status"] == "in_progress"), None)}
                 for job in jobs]}]


def watch_build(run_id: int | None) -> int:
    """Stay attached until the current run finishes, with bounded network backoff."""
    previous = None
    failures = 0
    candidate = None if run_id else json.loads((EVIDENCE / "LATEST.json").read_text(encoding="utf8"))
    while True:
        try:
            runs = package_status(run_id) if run_id else read_status(candidate)
            failures = 0
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            failures += 1
            code = getattr(error, "code", None)
            print(json.dumps({"network_retry": failures, "http_status": code,
                              "error_type": type(error).__name__}), flush=True)
            if code in (401, 403, 404) or failures >= 6:
                return 2
            time.sleep(min(10 * 2 ** failures, 60))
            continue
        signature = json.dumps(runs, sort_keys=True, ensure_ascii=False)
        if signature != previous:
            print(json.dumps({"at_utc": datetime.now(timezone.utc).isoformat(), "runs": runs},
                             ensure_ascii=False), flush=True)
            previous = signature
        if runs and all(run["status"] == "completed" for run in runs):
            return 0 if all(run["conclusion"] == "success" for run in runs) else 1
        time.sleep(30)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-run", type=int)
    options = parser.parse_args()
    raise SystemExit(watch_build(options.package_run))
