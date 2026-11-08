"""Download the user's public source definitions serially and inventory compatibility needs.

Usage: python -B -X utf8 scripts/audit_publisher_sources.py
Keeps original definitions outside the repository; never prints embedded values or credentials.
This inventories definitions only and does not claim their reading pipelines passed.
"""
import hashlib
import json
from pathlib import Path
import re
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path("F:/SourceReadSwift/project-audit-20261106/sources/publisher")


def main():
    entries = json.loads((ROOT / "docs/project-audit-20261106/SOURCE-PUBLISHER-LINKS.json").read_text(encoding="utf8"))["entries"]
    OUTPUT.mkdir(parents=True, exist_ok=True)
    reports = []
    for index, entry in enumerate(entries):
        destination = OUTPUT / f"source-{index + 1:02}.json"
        report = {"name": entry["name"], "definition_path": str(destination), "reading_pipeline": "not_verified"}
        try:
            if not destination.exists():
                request = urllib.request.Request(entry["importURL"], headers={"User-Agent": "SourceReadSwift-compatibility-audit"})
                with urllib.request.urlopen(request, timeout=20) as response:
                    payload = response.read(2 * 1024 * 1024 + 1)
                if len(payload) > 2 * 1024 * 1024:
                    raise ValueError("Definition exceeds 2 MiB")
                destination.write_bytes(payload)
            payload = destination.read_bytes()
            decoded = json.loads(payload)
            sources = decoded if isinstance(decoded, list) else [decoded]
            report.update(bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest(), sources=len(sources))
            report["capabilities"] = []
            for source in sources:
                script = json.dumps(source, ensure_ascii=False)
                report["capabilities"].append({
                    "name": source.get("bookSourceName", "unnamed"),
                    "source_type": source.get("bookSourceType"),
                    "has_search": bool(source.get("searchUrl")),
                    "has_login": bool(source.get("loginUrl") or source.get("loginUi")),
                    "has_jslib": bool(source.get("jsLib")),
                    "java_methods": sorted(set(re.findall(r"java\.([A-Za-z_][\w]*)\s*\(", script))),
                    "android_bridges": sorted(set(re.findall(r"(?:Packages|android|org|cn)\.[A-Za-z_$][\w.$]+", script))),
                })
        except (urllib.error.URLError, ValueError, OSError, TypeError, AttributeError) as error:
            report["failure"] = type(error).__name__
        reports.append(report)
        print(json.dumps(report, ensure_ascii=False), flush=True)
        (ROOT / "docs/project-audit-20261106/PUBLISHER-COMPATIBILITY.json").write_text(
            json.dumps(reports, ensure_ascii=False, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    main()
