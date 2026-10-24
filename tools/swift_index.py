#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build a reviewable index of every Swift file: size, declared types, and member names.

This is the "内核笔记" artifact: it lets any later reader (human or model) jump to a
file and symbol without re-reading 76k lines, and it is generated, not hand-written.
"""
import os
import re
import sys

ROOT = r"D:\Gemini反重力\SourceReadSwift2\SourceReadSwift"
OUT = r"D:\Gemini反重力\SourceReadSwift2\docs\内核笔记-全量索引.md"

TYPE_RE = re.compile(r"^(?:public |private |fileprivate |internal |@\w+\s+)*(struct|final class|class|enum|protocol|extension|actor)\s+([A-Za-z_][\w]*)")
FUNC_RE = re.compile(r"^\s{0,8}(?:public |private |fileprivate |internal |@\w+\s+|static |class )*func\s+([A-Za-z_][\w]*)")
VAR_RE = re.compile(r"^\s{0,8}(?:public |private |fileprivate |internal |@\w+\s+|static )*(?:var|let)\s+([A-Za-z_][\w]*)\s*[:=]")
MARK_RE = re.compile(r"^\s*//\s*MARK:\s*-?\s*(.+)$")


def scan(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    types, funcs, marks = [], [], []
    for line in lines:
        m = TYPE_RE.match(line)
        if m:
            types.append(f"{m.group(1)} {m.group(2)}")
            continue
        m = FUNC_RE.match(line)
        if m:
            funcs.append(m.group(1))
            continue
        m = MARK_RE.match(line)
        if m:
            marks.append(m.group(1).strip())
    return len(lines), types, funcs, marks


def main():
    rows = []
    for dirpath, _dirnames, filenames in os.walk(ROOT):
        for name in sorted(filenames):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            count, types, funcs, marks = scan(path)
            rows.append((rel, count, types, funcs, marks))
    rows.sort(key=lambda r: (-r[1], r[0]))

    total_lines = sum(r[1] for r in rows)
    out = []
    out.append("# 内核笔记 · 全量索引")
    out.append("")
    out.append("> 由 `tools/swift_index.py` 扫描生成，覆盖 `SourceReadSwift/` 下全部 %d 个 Swift 文件、%d 行。" % (len(rows), total_lines))
    out.append("> 用途：定位文件与符号，不用再整篇读代码。修改任何文件前先在这里查它的类型与函数清单。")
    out.append("")
    out.append("## 按体积排序（前 25）")
    out.append("")
    out.append("| 行数 | 文件 | 类型数 | 函数数 |")
    out.append("|---:|---|---:|---:|")
    for rel, count, types, funcs, _marks in rows[:25]:
        out.append("| %d | `%s` | %d | %d |" % (count, rel, len(types), len(funcs)))
    out.append("")
    out.append("## 分层统计")
    out.append("")
    buckets = {}
    for rel, count, _types, _funcs, _marks in rows:
        key = rel.split("/")[0]
        b = buckets.setdefault(key, [0, 0])
        b[0] += 1
        b[1] += count
    out.append("| 目录 | 文件 | 行数 |")
    out.append("|---|---:|---:|")
    for key in sorted(buckets):
        out.append("| `%s/` | %d | %d |" % (key, buckets[key][0], buckets[key][1]))
    out.append("")
    out.append("## 逐文件索引")
    out.append("")
    for rel, count, types, funcs, marks in rows:
        out.append("### `%s` — %d 行" % (rel, count))
        if marks:
            out.append("")
            out.append("段落： " + " · ".join(marks[:12]))
        out.append("")
        if types:
            out.append("- 类型：" + "、".join("`%s`" % t for t in types[:20]))
        if funcs:
            shown = funcs[:28]
            out.append("- 函数：" + "、".join("`%s`" % f for f in shown) + ("…（共 %d）" % len(funcs) if len(funcs) > len(shown) else ""))
        out.append("")
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print("wrote", OUT, len(out), "lines")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
