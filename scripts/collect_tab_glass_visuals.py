"""Collect same-commit tab screenshots serially without downloading whole test bundles.

Usage: python -B -X utf8 scripts/collect_tab_glass_visuals.py <COMMIT> <RUN_ID>
Original attachments stay intact; model previews must pass the 1 MiB size check.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile
import zlib

from prepare_model_image import prepare_model_image
from verify_reader_quality import EVIDENCE, github, run_git

sys.path.insert(0, str(EVIDENCE.parent))
from select_visual import ReadOnlyRange, location


def collect_visuals(head: str, run_id: int) -> list[dict]:
    """Preserve labeled home screenshots with per-file hashes and bounded previews."""
    head = run_git("rev-parse", "--verify", head + "^{commit}")
    run = github.api(f"actions/runs/{run_id}")
    if run["head_sha"] != head:
        raise ValueError("Requested visual commit does not match the workflow run")
    artifacts = github.api(f"actions/runs/{run_id}/artifacts?per_page=50")["artifacts"]
    folder = EVIDENCE / head / "tab-glass-visuals"
    receipts = []
    for artifact in artifacts:
        if not artifact["name"].startswith("tab-glass-" + head + "-ios") or artifact["expired"]:
            continue
        runtime = artifact["name"].rsplit("-", 1)[-1]
        destination = folder / runtime
        destination.mkdir(parents=True, exist_ok=True)
        reader = ReadOnlyRange(location(artifact), artifact["size_in_bytes"])
        with zipfile.ZipFile(reader) as archive:
            for name in archive.namelist():
                if not name.endswith("manifest.json"):
                    continue
                manifest = archive.read(name)
                for case in json.loads(manifest):
                    for attachment in case.get("attachments", []):
                        label = attachment.get("suggestedHumanReadableName", "")
                        entry = attachment.get("exportedFileName", "")
                        if not label.startswith("root-tab-glass-real-home-") or not entry.endswith(".png"):
                            continue
                        source = (Path(name).parent / entry).as_posix()
                        size = archive.getinfo(source).file_size
                        if not 0 < size < 8 * 1024 * 1024:
                            raise ValueError("Expected a tab screenshot smaller than 8 MiB")
                        target = destination / Path(entry).name
                        picture = target.read_bytes() if target.exists() else b""
                        if len(picture) != size or zlib.crc32(picture) != archive.getinfo(source).CRC:
                            picture = archive.read(source)
                            target.write_bytes(picture)
                        receipts.append({"runtime": runtime, "label": label, "path": str(target),
                            "bytes": len(picture), "sha256": hashlib.sha256(picture).hexdigest(),
                            "model_preview": prepare_model_image(target, destination / "model-previews")})
        print(json.dumps({"artifact": artifact["id"], "runtime": runtime,
            "downloaded_bytes": reader.bytes_read}), flush=True)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "SELECTED.json").write_text(json.dumps(receipts, ensure_ascii=False, indent=2), encoding="utf8")
    return receipts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("head")
    parser.add_argument("run", type=int)
    options = parser.parse_args()
    print(json.dumps(collect_visuals(options.head, options.run), ensure_ascii=False))
