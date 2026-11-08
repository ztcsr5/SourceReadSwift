"""Follow the provided UXX source's public novel HTML path serially.

Usage: python -B -X utf8 scripts/probe_uxx_pipeline.py
This checks HTTP/HTML boundaries only. Native engine replay remains a separate gate.
Original responses stay outside the repository; report contains counts and hashes, not chapter text.
"""
import hashlib
import json
from pathlib import Path
import re
import urllib.request
from urllib.parse import urljoin

from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path("F:/SourceReadSwift/project-audit-20261106/sources/uxx-pipeline")


def fetch(label, url):
    path = OUTPUT / (label + ".html")
    if path.exists():
        payload = path.read_bytes()
    else:
        request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Referer": "https://uxxtv.com/"})
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = response.read(2 * 1024 * 1024 + 1)
        if len(payload) > 2 * 1024 * 1024:
            raise ValueError("Response exceeds 2 MiB")
        path.write_bytes(payload)
    return payload.decode("utf8", errors="replace"), {"stage": label, "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(), "path": str(path)}


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    reports = []
    try:
        search = BeautifulSoup((OUTPUT.parent / "uxx-search.txt").read_text(encoding="utf8"), "html.parser")
        cover = search.select_one(".list_1_box ul > li .cover_box a, .list_3_box ul > li .cover_box a")
        identifier = re.search(r"/(?:show|play)/(\d+)", cover["href"]).group(1)
        detail_url = f"https://uxxtv.com/show/{identifier}.html?uxt=2"
        detail, report = fetch("detail", detail_url)
        parsed = BeautifulSoup(detail, "html.parser")
        chapters = parsed.select(".catalog_ul li a")
        report.update(title_found=bool(parsed.select_one(".info_box h1")),
                      intro_characters=len(parsed.select_one(".brief").get_text()) if parsed.select_one(".brief") else 0,
                      chapters=len(chapters))
        reports.append(report)
        if not chapters:
            raise ValueError("No chapters matched the source rule")
        chapter_url = urljoin(detail_url, chapters[0]["href"])
        chapter, report = fetch("chapter", chapter_url)
        reports.append(report)
        embedded = re.search(r"_getcontent\.php\?([^\"'<>\s]+)", chapter)
        if not embedded:
            raise ValueError("No content endpoint matched the source rule")
        body, report = fetch("content", "https://uxxtv.com/_getcontent.php?" + embedded.group(1))
        parsed_body = BeautifulSoup(body, "html.parser")
        for node in parsed_body.select("script, style"):
            node.decompose()
        report["text_characters"] = len(parsed_body.get_text(strip=True))
        reports.append(report)
        verdict = "http_html_path_completed_not_native_engine_validation"
    except Exception as error:
        verdict = type(error).__name__
    outcome = {"scope": "One public first novel result and first chapter; no credentials or purchases", "verdict": verdict, "stages": reports}
    (ROOT / "docs/project-audit-20261106/UXX-HTTP-PIPELINE.json").write_text(json.dumps(outcome, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps(outcome, ensure_ascii=False))


if __name__ == "__main__":
    main()
