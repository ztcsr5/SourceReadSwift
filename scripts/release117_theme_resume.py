"""Make existing themed list rows reactive without recreating screens/editors.
Usage: python -X utf8 scripts/release117_theme_resume.py
Only replaces the exact existing static themed-row modifier; preserves file bytes otherwise.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
changed = []
for path in sorted((ROOT / "SourceReadSwift").rglob("*.swift")):
    before = path.read_bytes()
    needle = b".listRowBackground(AppTheme.card)"
    if needle not in before:
        continue
    after = before.replace(needle, b".listRowBackground(AppThemeRowSurface())")
    path.write_bytes(after)
    changed.append({"path": str(path.relative_to(ROOT)), "rows": before.count(needle),
                    "before_sha256": hashlib.sha256(before).hexdigest(), "after_sha256": hashlib.sha256(after).hexdigest()})
output = Path("F:/SourceReadSwift/release-1.1.7/theme17/row-reactivity.json")
output.write_text(json.dumps(changed, ensure_ascii=False, indent=2), encoding="utf-8")
print("Reactive theme rows:", sum(row["rows"] for row in changed), "in", len(changed), "files")
