"""Collect selected native PNG evidence without downloading every XCTest video.

Usage: python -B -X utf8 scripts/collect_reader_visuals.py
Uses the current reader snapshot and the existing bounded ZIP range transport.
"""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import sys
import zipfile

from verify_reader_quality import EVIDENCE, github
from prepare_model_image import prepare_model_image

sys.path.insert(0, str(EVIDENCE.parent))
from select_visual import ReadOnlyRange, location

PREFIXES = (
    "release116-theme-", "release116-workbench-", "release116-reader-top-",
    "floating-desk-01-pearl-", "floating-desk-20-", "floating-desk-21-", "floating-desk-22-",
    "floating-desk-23-", "floating-desk-24-",
    "floating-desk-25-", "floating-desk-26-",
    "floating-desk-10-dark-", "floating-desk-11-", "floating-desk-16-",
    "floating-desk-17-", "floating-desk-cross-chapter-",
    "reader-more-open-5", "reader-more-dismissal-failure-", "reader-returned-root", "reader-curl-forward-",
    "reader-menu-real-", "reader-settings-real-home", "comic-", "cbz-",
)


def collect_artifact(artifact, folder):
    folder.mkdir(parents=True, exist_ok=True)
    signed = location(artifact)
    selected = {}
    with zipfile.ZipFile(ReadOnlyRange(signed, artifact["size_in_bytes"])) as archive:
        for name in archive.namelist():
            if not name.endswith("manifest.json"):
                continue
            manifest = archive.read(name)
            (folder / name.replace("/", "-")).write_bytes(manifest)
            for case in json.loads(manifest):
                for attachment in case.get("attachments", []):
                    label = attachment["suggestedHumanReadableName"].split("_0_", 1)[0]
                    filename = attachment["exportedFileName"]
                    if filename.endswith(".png") and label.startswith(PREFIXES):
                        selected.setdefault(label, (Path(name).parent / filename).as_posix())

    def fetch_screenshot(pair):
        label, entry = pair
        target = folder / Path(entry).name
        if not target.exists():
            with zipfile.ZipFile(ReadOnlyRange(signed, artifact["size_in_bytes"])) as archive:
                content = archive.read(entry)
            with target.open("xb") as output:
                output.write(content)
        content = target.read_bytes()
        return {"label": label, "path": str(target), "bytes": len(content),
                "sha256": hashlib.sha256(content).hexdigest(),
                "model_preview": prepare_model_image(target, folder / "model-previews")}

    with ThreadPoolExecutor(max_workers=4) as workers:
        screenshots = list(workers.map(fetch_screenshot, sorted(selected.items())))
    receipt = {"artifact": artifact["id"], "name": artifact["name"], "screenshots": screenshots}
    (folder / "SELECTED.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf8")
    return receipt


def collect_visuals():
    candidate = json.loads((EVIDENCE / "LATEST.json").read_text(encoding="utf8"))
    runs = github.api("actions/runs?head_sha=" + candidate["head"] + "&per_page=30")["workflow_runs"]
    run = next(run for run in runs if run["path"] == ".github/workflows/ios.yml")
    artifacts = github.api(f"actions/runs/{run['id']}/artifacts?per_page=50")["artifacts"]
    selected = [a for a in artifacts if not a["expired"] and candidate["head"] in a["name"]
                and a["name"].startswith(("ios-ui-snapshots-", "ios26-ui-snapshots-"))]
    if len(selected) != 2:
        raise RuntimeError("Both native snapshot artifacts must exist before collecting final visuals")
    folder = EVIDENCE / candidate["head"]
    receipts = [collect_artifact(artifact, folder / artifact["name"]) for artifact in selected]
    (folder / "VISUAL_INDEX.json").write_text(json.dumps(receipts, ensure_ascii=False, indent=2), encoding="utf8")
    return {"head": candidate["head"], "run": run["id"], "artifacts": len(receipts),
            "screenshots": sum(len(receipt["screenshots"]) for receipt in receipts), "folder": str(folder)}


if __name__ == "__main__":
    print(json.dumps(collect_visuals(), ensure_ascii=False))
