"""Match exported rule identities to a source report; optionally compare a retest.

Usage: python scripts/audit_source_report_matrix.py --rules <RULES.json>
       --baseline <REPORT.json> [--candidate <RETEST.json>] [--out <SUMMARY.json>]

Only hashed source identities, stage states and counts are emitted.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


STAGES = ("search", "detail", "toc", "content")
NOT_RUN = "not_run"


def read_json(path: Path) -> object:
    """Read a local export without evaluating any attached rule scripts."""
    return json.loads(path.read_text(encoding="utf-8-sig"))


def index_rows(rows: object, key: str, label: str) -> dict[str, dict]:
    """Require unique exact identities; do not accidentally match by display name."""
    if not isinstance(rows, list) or not rows:
        raise ValueError(f"{label} must contain a nonempty array")
    indexed = {}
    for number, row in enumerate(rows, start=1):
        identity = row.get(key) if isinstance(row, dict) else None
        if not isinstance(identity, str) or not identity.strip():
            raise ValueError(f"{label} row {number} has no source identity")
        identity = identity.strip()
        if identity in indexed:
            raise ValueError(f"{label} row {number} has a duplicate source identity")
        indexed[identity] = row
    return indexed


def collect_report(report: object) -> tuple[str, dict[str, tuple[str, ...]]]:
    """Extract four ordered stage states; an omitted stage can never pass."""
    if not isinstance(report, dict) or not isinstance(report.get("keyword"), str):
        raise ValueError("report is missing its keyword")
    keyword = report["keyword"].strip()
    if not keyword:
        raise ValueError("report keyword is blank")
    indexed = index_rows(report.get("reports"), "sourceURL", "report")
    outcomes = {}
    for identity, row in indexed.items():
        if str(row.get("keyword", keyword)).strip() != keyword:
            raise ValueError("a source row used a different keyword")
        steps = row.get("steps")
        if not isinstance(steps, list) or len(steps) > len(STAGES):
            raise ValueError("report has an invalid number of source stages")
        states = []
        for stage, step in zip(STAGES, steps):
            if not isinstance(step, dict) or step.get("stage") != stage or not isinstance(step.get("status"), str):
                raise ValueError("report has missing or out-of-order source stages")
            states.append(step["status"])
        outcomes[identity] = tuple(states + [NOT_RUN] * (len(STAGES) - len(states)))
    return keyword, outcomes


def count_stages(outcomes: dict[str, tuple[str, ...]]) -> dict:
    """Count report states and four-stage passes, separately from cohort coverage."""
    stages = {stage: dict(sorted(Counter(states[i] for states in outcomes.values()).items()))
              for i, stage in enumerate(STAGES)}
    return {"stages": stages, "all_passed": sum(all(value == "passed" for value in states)
                                               for states in outcomes.values())}


def audit_batch(rules: object, baseline: object, candidate: object | None = None) -> dict:
    """Compare only reports with the same exact cohort and keyword."""
    rule_ids = index_rows(rules, "bookSourceUrl", "rules").keys()
    keyword, previous = collect_report(baseline)
    if rule_ids != previous.keys():
        raise ValueError(f"rules do not match baseline: {len(rule_ids - previous.keys())} extra, "
                         f"{len(previous.keys() - rule_ids)} missing")
    summary = {"keyword": keyword, "sources": len(previous), "baseline": count_stages(previous),
               "candidate": None, "rows": []}
    current = {}
    if candidate is not None:
        test_keyword, current = collect_report(candidate)
        if keyword != test_keyword:
            raise ValueError("candidate keyword does not match baseline")
        if current.keys() != previous.keys():
            raise ValueError(f"candidate cohort mismatch: {len(current.keys() - previous.keys())} extra, "
                             f"{len(previous.keys() - current.keys())} missing")
        summary["candidate"] = count_stages(current)
    for identity in sorted(previous):
        summary["rows"].append({
            "source_key": hashlib.sha256(identity.encode("utf-8")).hexdigest(),
            "baseline": dict(zip(STAGES, previous[identity])),
            "candidate": dict(zip(STAGES, current[identity])) if identity in current else None,
        })
    return summary


def main() -> int:
    """Return nonzero for a bad cohort or malformed report."""
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--rules", type=Path, required=True)
    cli.add_argument("--baseline", type=Path, required=True)
    cli.add_argument("--candidate", type=Path)
    cli.add_argument("--out", type=Path)
    args = cli.parse_args()
    try:
        candidate = read_json(args.candidate) if args.candidate else None
        if args.candidate and candidate is None:
            raise ValueError("candidate report is null")
        summary = audit_batch(read_json(args.rules), read_json(args.baseline), candidate)
        if args.out:
            args.out.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (ValueError, OSError) as error:
        cli.exit(1, f"Source audit failed: {error}\n")
    print(json.dumps({key: value for key, value in summary.items() if key != "rows"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
