import sys, json, urllib.request, subprocess
from pathlib import Path

ROOT = Path(r"D:\Gemini反重力\SourceReadSwift2")
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "docs/reader-recovery-119"))

from verify_reader_quality import snapshot_tree, run_git, github

tree, selected = snapshot_tree()
print(f"Snapshot tree: {tree} ({len(selected)} files)")

head_commit = run_git("rev-parse", "HEAD")
commit_msg = "build(release): SourceRead 1.1.8 Build 138 with master app icon, seamless scroll, and global search on tab bar"
commit = run_git("commit-tree", tree, "-p", head_commit, "-m", commit_msg)
print(f"Created commit: {commit}")

branch = "codex/release-1.1.8"
print(f"Pushing to origin {branch}...")
push_out = run_git("push", "-f", "origin", f"{commit}:refs/heads/{branch}")
print(f"Push completed: {push_out}")

# Trigger unsigned-ipa.yml
try:
    req = urllib.request.Request(
        f"https://api.github.com/repos/{github.REPO}/actions/workflows/unsigned-ipa.yml/dispatches",
        data=json.dumps({"ref": branch}).encode("utf8"),
        headers=github.HEADERS,
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(f"Workflow dispatch status: {resp.status}")
except Exception as e:
    print(f"Dispatch info/fallback: {e}")

print(f"SUCCESS: Branch {branch} updated with commit {commit}")
