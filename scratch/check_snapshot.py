import plistlib
from pathlib import Path

p = Path("F:/SourceReadSwift/reader-quality-137/verification/snapshots-c906860/gestures/1B4352B9-7E3B-4B2A-8A30-F19BC91ACE52")
pl = plistlib.loads(p.read_bytes())
objs = [s for s in pl.get("$objects", []) if isinstance(s, str)]
keywords = ["reader", "shelf", "剑来", "hittable", "webscroll", "button", "statictext", "tab"]
found = [s for s in objs if any(k in s.lower() for k in keywords)]
for s in found[:40]:
    print(s)
