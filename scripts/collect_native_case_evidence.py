"""Collect one XCTest case's original attachments with bounded ZIP reads.

Usage: python -B -X utf8 scripts/collect_native_case_evidence.py <SHA> <RUN_ID> <CASE_SUBSTRING>
Preserves originals and produces checked model previews of PNG attachments.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

from verify_reader_quality import EVIDENCE, github
from prepare_model_image import prepare_model_image

sys.path.insert(0, str(EVIDENCE.parent))
from select_visual import ReadOnlyRange, location


def collect_case(head, run_id, case_name):
    run = github.api(f"actions/runs/{run_id}")
    if run["head_sha"] != head:
        raise ValueError("The run does not match the requested commit")
    folder = EVIDENCE / head / ("case-" + hashlib.sha256(case_name.encode()).hexdigest()[:12])
    folder.mkdir(parents=True, exist_ok=True)
    records = []
    for artifact in github.api(f"actions/runs/{run_id}/artifacts?per_page=50")["artifacts"]:
        if artifact["expired"] or not artifact["name"].startswith(("ios-ui-snapshots-", "ios26-ui-snapshots-")):
            continue
        if head not in artifact["name"]:
            raise ValueError("The attachment archive does not match the requested commit")
        with zipfile.ZipFile(ReadOnlyRange(location(artifact), artifact["size_in_bytes"])) as archive:
            selected = {}
            for name in archive.namelist():
                if not name.endswith("manifest.json"):
                    continue
                for case in json.loads(archive.read(name)):
                    identity = case.get("testIdentifier", "") + case.get("testName", "")
                    if case_name not in identity:
                        continue
                    for attachment in case.get("attachments", []):
                        entry = (Path(name).parent / attachment["exportedFileName"]).as_posix()
                        selected[entry] = attachment.get("suggestedHumanReadableName", entry)
            for entry, label in selected.items():
                member = archive.getinfo(entry)
                if member.file_size > 32 * 1024 * 1024:
                    records.append({"label": label, "bytes": member.file_size, "skipped": "exceeds bounded read"})
                    continue
                target = folder / str(artifact["id"]) / Path(entry).name
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.exists():
                    target.write_bytes(archive.read(entry))
                content = target.read_bytes()
                record = {"artifact": artifact["id"], "label": label, "path": str(target),
                          "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}
                if target.suffix.lower() == ".png":
                    record["model_preview"] = prepare_model_image(target, target.parent / "model-previews")
                records.append(record)
    receipt = folder / "SELECTED.json"
    receipt.write_text(json.dumps({"head": head, "run": run_id, "case": case_name, "attachments": records},
                                 ensure_ascii=False, indent=2), encoding="utf8")
    return {"receipt": str(receipt), "attachments": len(records)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("head")
    parser.add_argument("run", type=int)
    parser.add_argument("case")
    arguments = parser.parse_args()
    print(json.dumps(collect_case(arguments.head, arguments.run, arguments.case), ensure_ascii=False))
