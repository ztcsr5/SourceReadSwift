import io, json, os, plistlib, sys, time, zipfile, hashlib
from pathlib import Path

ROOT = Path(r"D:\Gemini反重力\SourceReadSwift2")
sys.path.insert(0, str(ROOT / "docs/reader-recovery-119"))
import ci_status as ci

RUN_ID = 42391521170
print(f"Monitoring run {RUN_ID} (SourceRead 1.1.8 Build 138 - commit 909fc78)...")

while True:
    run = ci.api(f"actions/runs/{RUN_ID}")
    status = run["status"]
    conclusion = run["conclusion"]
    print(f"Run {RUN_ID}: status={status}, conclusion={conclusion}")
    if status == "completed":
        if conclusion != "success":
            # fetch failure logs
            jobs = ci.api(f"actions/runs/{RUN_ID}/jobs")["jobs"]
            for j in jobs:
                print(f"Job {j['name']} conclusion: {j['conclusion']}")
                try:
                    log = ci.signed_download(f"actions/jobs/{j['id']}/logs").decode("utf8", errors="replace")
                    for line in log.splitlines()[-40:]:
                        print("  " + line)
                except Exception as e:
                    print(f"Could not read log: {e}")
            raise SystemExit(f"Run failed with conclusion: {conclusion}")
        break
    time.sleep(15)

print("Run completed successfully! Fetching artifacts...")
artifacts = ci.api(f"actions/runs/{RUN_ID}/artifacts")["artifacts"]
target_artifact = next((a for a in artifacts if a["name"] == "SourceReadSwift-unsigned-ipa"), None)
if not target_artifact:
    raise SystemExit("Artifact SourceReadSwift-unsigned-ipa not found")

print(f"Downloading artifact {target_artifact['id']} ({target_artifact['size_in_bytes']} bytes)...")
zip_bytes = ci.signed_download(f"actions/artifacts/{target_artifact['id']}/zip")

ipa_bytes = None
ipa_filename = None
with zipfile.ZipFile(io.BytesIO(zip_bytes)) as z:
    for name in z.namelist():
        if name.lower().endswith(".ipa"):
            ipa_bytes = z.read(name)
            ipa_filename = name
            break

if not ipa_bytes:
    raise SystemExit("No .ipa file found in artifact zip")

digest = hashlib.sha256(ipa_bytes).hexdigest()
size_bytes = len(ipa_bytes)
print(f"Extracted {ipa_filename}: {size_bytes} bytes, SHA-256: {digest}")

# Verify plist
with zipfile.ZipFile(io.BytesIO(ipa_bytes)) as z:
    assert z.testzip() is None, "Corrupted IPA zip"
    plist_name = next(n for n in z.namelist() if n.startswith("Payload/") and n.count("/") == 2 and n.endswith(".app/Info.plist"))
    plist = plistlib.loads(z.read(plist_name))

version = plist.get("CFBundleShortVersionString")
build = plist.get("CFBundleVersion")
name = plist.get("CFBundleDisplayName", "纸间")
print(f"Verified Info.plist: Version={version}, Build={build}, DisplayName={name}")
assert version == "1.1.8", f"Unexpected version: {version}"
assert build == "138", f"Unexpected build: {build}"

# Write to Desktop
desktop_path = Path.home() / "Desktop" / "SourceReadSwift-1.1.8-build138-unsigned.ipa"
desktop_path.write_bytes(ipa_bytes)
print(f"SUCCESS: Written IPA to Desktop: {desktop_path}")

# Write to local builds folder
local_folder = ROOT / "build"
local_folder.mkdir(parents=True, exist_ok=True)
(local_folder / "SourceReadSwift-1.1.8-build138-unsigned.ipa").write_bytes(ipa_bytes)
print(f"SUCCESS: Written IPA to workspace: {local_folder / 'SourceReadSwift-1.1.8-build138-unsigned.ipa'}")

result_info = {
    "run_id": RUN_ID,
    "version": version,
    "build": build,
    "desktop_path": str(desktop_path),
    "size_bytes": size_bytes,
    "sha256": digest
}
print(json.dumps(result_info, indent=2, ensure_ascii=False))
