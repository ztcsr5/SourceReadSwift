#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Static field-coverage probe for the unpacked IPAs.

Scans each app's main binary for Legado/JSON book-source field names and reader
mode symbols, in both ASCII and UTF-16LE encodings. Pure static read; nothing is
executed. Output is a matrix: app x keyword -> occurrence count.
"""
import os
import re
import sys

DESK = r"C:\Users\Edc21\Desktop"
APPS = {
    "栖阅": [r"栖阅2027.01.01\Payload\栖阅.app\栖阅"],
    "香色闺阁": [r"香色闺阁\Payload\StandarReader.app\StandarReader"],
    "源阅读": [r"源阅读\Payload\SourceRead.app\SourceRead"],
    "源阅": [r"源阅_1.0TF_112\Payload\SourceRead.app\SourceRead"],
    "yidaApp": [r"yidaApp-1.4.4-release-nosign\Payload\Runner.app\Frameworks\App.framework\App",
                r"yidaApp-1.4.4-release-nosign\Payload\Runner.app\Runner"],
}

SOURCE_FIELDS = [
    "bookSourceUrl", "bookSourceName", "bookSourceGroup", "bookSourceType",
    "searchUrl", "ruleSearch", "ruleBookInfo", "ruleToc", "ruleContent", "ruleExplore",
    "nextTocUrl", "nextContentUrl", "isVolume", "formatJs", "preUpdateJs", "reverseToc",
    "imageDecode", "imageStyle", "payAction", "sourceRegex", "downloadUrls",
    "loginUrl", "loginUi", "loginCheckJs", "jsLib", "enabledCookieJar",
    "bookUrlPattern", "tocUrl", "wordCount", "variableComment", "customOrder",
]

READER_SYMBOLS = [
    "UIPageViewController", "CATransition", "pageCurl", "PageCurl",
    "UIScrollView", "scrollMode", "doublePage", "VolumeButton",
]

ALL = SOURCE_FIELDS + READER_SYMBOLS


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def count_all(data, keyword):
    ascii_hits = data.count(keyword.encode("utf-8"))
    utf16_hits = data.count(keyword.encode("utf-16-le"))
    return ascii_hits + utf16_hits


def main():
    report = {}
    for app, rels in APPS.items():
        counts = {k: 0 for k in ALL}
        bytes_total = 0
        for rel in rels:
            path = os.path.join(DESK, rel)
            if not os.path.exists(path):
                print("MISSING", path)
                continue
            data = read_bytes(path)
            bytes_total += len(data)
            for key in ALL:
                counts[key] += count_all(data, key)
        report[app] = counts
        print(f"{app}: scanned {bytes_total/1048576:.1f} MB")

    # matrix output
    header = "| 字段 | " + " | ".join(APPS.keys()) + " |"
    print("\n" + header)
    print("|---|" + "---|" * len(APPS))
    for key in ALL:
        row = [str(report.get(app, {}).get(key, 0)) for app in APPS]
        print(f"| `{key}` | " + " | ".join(row) + " |")

    # summary: which fields appear in at least one competitor
    print("\n字段出现情况：")
    present = [k for k in SOURCE_FIELDS if any(report[a][k] for a in report)]
    absent = [k for k in SOURCE_FIELDS if not any(report[a][k] for a in report)]
    print("  出现:", len(present), ",".join(present))
    print("  未出现:", len(absent), ",".join(absent))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
