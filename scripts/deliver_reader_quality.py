"""Package or verify the reviewed reader snapshot without changing the checkout.

Usage: python -B -X utf8 scripts/deliver_reader_quality.py dispatch|deliver
Requires the existing local evidence tools and VISUAL_REVIEW.json for the same SHA.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import io
import os
import shutil
import sys
import tempfile
import urllib.request
import zipfile

from verify_reader_quality import EVIDENCE, github, snapshot_tree, run_git


def read_candidate():
    candidate = json.loads((EVIDENCE / "LATEST.json").read_text(encoding="utf8"))
    require_current_snapshot(candidate)
    folder = EVIDENCE / candidate["head"]
    review = json.loads((folder / "VISUAL_REVIEW.json").read_text(encoding="utf8"))
    if review.get("head") != candidate["head"] or review.get("acceptable") is not True:
        raise RuntimeError("The candidate has no accepted visual review for its SHA")
    ref = github.api("git/ref/heads/" + candidate["branch"])
    if ref["object"]["sha"] != candidate["head"]:
        raise RuntimeError("The packaging branch no longer points to the reviewed SHA")
    runs = github.api("actions/runs?head_sha=" + candidate["head"] + "&per_page=30")["workflow_runs"]
    native = next(run for run in runs if run["path"] == ".github/workflows/ios.yml")
    if native["conclusion"] != "success":
        raise RuntimeError("The same-SHA native regression workflow has not passed")
    jobs = github.api(f"actions/runs/{native['id']}/jobs?per_page=50")["jobs"]
    require_native_steps(jobs)
    return candidate, folder, runs, native


def require_native_steps(jobs):
    required_steps = {
        "build": {"Test"},
        "native-tabs": {"iOS26 native tab runtime regression",
                        "Exercise real reader settings UI on iOS26",
                        "Exercise reader chapter continuity on iOS26",
                        "Exercise reader return gestures on iOS26",
                        "Exercise twenty native reader return cycles on iOS26"},
    }
    for name, steps in required_steps.items():
        job = next((job for job in jobs if job["name"] == name), None)
        if job is None or job["conclusion"] != "success":
            raise RuntimeError(f"Native job {name} has not passed")
        passed = {step["name"] for step in job["steps"] if step["conclusion"] == "success"}
        if missing := sorted(steps - passed):
            raise RuntimeError(f"Required steps did not pass in {name}: {', '.join(missing)}")


def require_current_snapshot(candidate):
    tree, _ = snapshot_tree()
    if tree != candidate["tree"]:
        raise RuntimeError("Current workspace differs from the verified snapshot; run native tests on the new tree")


def hash_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as payload:
        for block in iter(lambda: payload.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def package_filename(plist: dict, head: str) -> str:
    """Name the desktop package from verified metadata, with safe path components."""
    version, build = plist["CFBundleShortVersionString"], plist["CFBundleVersion"]
    if not re.fullmatch(r"[0-9.]+", version) or not re.fullmatch(r"[0-9]+", build) or not re.fullmatch(r"[0-9a-f]{40}", head):
        raise ValueError("Expected a numeric app version/build and full commit SHA")
    return f"SourceReadSwift-{version}-build{build}-{head[:7]}-unsigned.ipa"


def publish_verified_ipa(source, target, expected_sha256):
    """Publish only after a complete write, without replacing an existing artifact."""
    if target.exists():
        if hash_file(target) != expected_sha256:
            raise RuntimeError("Desktop already contains a different IPA under this name")
        return

    descriptor, name = tempfile.mkstemp(dir=target.parent, prefix=target.name + ".", suffix=".partial")
    staged = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as output, source.open("rb") as payload:
            shutil.copyfileobj(payload, output)
            output.flush()
            os.fsync(output.fileno())
        if hash_file(staged) != expected_sha256:
            raise RuntimeError("Desktop staging hash does not match the verified IPA")
        try:
            if os.name == "nt":
                staged.rename(target)
            else:
                os.link(staged, target)
        except FileExistsError:
            # Another delivery may have completed while this staging file was written.
            pass
        if hash_file(target) != expected_sha256:
            raise RuntimeError("Desktop already contains a different IPA under this name")
    finally:
        staged.unlink(missing_ok=True)


def dispatch_package():
    candidate, folder, runs, native = read_candidate()
    existing = next((run for run in runs if run["path"] == ".github/workflows/unsigned-ipa.yml"), None)
    if existing:
        return {"head": candidate["head"], "run": existing["id"], "status": existing["status"],
                "conclusion": existing["conclusion"], "dispatched": False}
    request = urllib.request.Request(
        "https://api.github.com/repos/" + github.REPO + "/actions/workflows/unsigned-ipa.yml/dispatches",
        data=json.dumps({"ref": candidate["branch"]}).encode("utf8"), headers=github.HEADERS, method="POST")
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 204:
            raise RuntimeError(f"IPA dispatch expected HTTP 204, received {response.status}")
    receipt = {"head": candidate["head"], "branch": candidate["branch"], "native_run": native["id"],
               "dispatched": True}
    (folder / "PACKAGE_DISPATCH.json").write_text(json.dumps(receipt, indent=2), encoding="utf8")
    return receipt


def deliver_package():
    candidate, folder, runs, native = read_candidate()
    package_run = next(run for run in runs if run["path"] == ".github/workflows/unsigned-ipa.yml")
    if package_run["conclusion"] != "success":
        raise RuntimeError("The reviewed device package has not built successfully")
    # Reuse the existing ZIP/font/arm64/dSYM verifier with the snapshot identity,
    # not the user's deliberately unchanged working-tree HEAD.
    source = EVIDENCE.parent / "verify_book_candidate.py"
    sys.path.insert(0, str(source.parent))
    spec = importlib.util.spec_from_file_location("reader_package_verification", source)
    verification = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verification)
    verification.github.HEAD = candidate["head"]
    verification.target = folder
    verification.select_run(package_run["id"])
    ipa = verification.read_payload(package_run["id"], "SourceReadSwift-unsigned-ipa", ".ipa")
    symbols = verification.read_payload(package_run["id"],
        "SourceReadSwift-device-symbols-" + candidate["head"], ".zip")
    from verify_device_ipa import verify_device_ipa
    project = run_git("show", candidate["head"] + ":project.yml")
    verified = verify_device_ipa(ipa, symbols, project, folder)
    with zipfile.ZipFile(io.BytesIO(ipa)) as package:
        plist = plistlib.loads(package.read("Payload/SourceReadSwift.app/Info.plist"))
        comic_type = "com.edc21.sourceread.cbz"
        declarations = plist.get("UTImportedTypeDeclarations", [])
        assert any(entry.get("UTTypeIdentifier") == comic_type for entry in declarations), "Missing CBZ UTI"
        assert any(comic_type in entry.get("LSItemContentTypes", [])
                   for entry in plist.get("CFBundleDocumentTypes", [])), "Missing CBZ document registration"
    filename = package_filename(plist, candidate["head"])
    output = folder / filename
    for path, payload in [(output, ipa), (folder / "SourceReadSwift-device-symbols.zip", symbols)]:
        if path.exists():
            assert path.read_bytes() == payload, f"Refusing to replace a different artifact: {path.name}"
        else:
            with path.open("xb") as destination:
                destination.write(payload)
    desktop = Path.home() / "Desktop" / filename
    fingerprint = hashlib.sha256(ipa).hexdigest()
    # A download can outlast edits made in another window.
    require_current_snapshot(candidate)
    publish_verified_ipa(output, desktop, fingerprint)
    receipt = verified | {"head": candidate["head"], "native_run": native["id"],
        "package_run": package_run["id"], "sha256": fingerprint, "bytes": len(ipa),
        "ipa": str(output), "desktop_ipa": str(desktop), "cbz_registered": True,
        "unsigned": True, "device_installed": False}
    (folder / "IPA_VERIFICATION.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf8")
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["dispatch", "deliver"])
    arguments = parser.parse_args()
    print(json.dumps(dispatch_package() if arguments.action == "dispatch" else deliver_package(), ensure_ascii=False))
