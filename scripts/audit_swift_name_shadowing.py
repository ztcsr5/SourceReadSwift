"""Detect Swift local declarations that shadow a method called in the same function.

Motivation: two real CI failures were "cannot call value of non-function type"
and "cannot be used as an instance member". tree-sitter syntax checks miss both.
This script is a narrow lint, not a compiler; findings require reading the code.
"""
import re, sys, io

def analyse(path):
    source = io.open(path, encoding="utf-8", newline="").read()
    lines = source.splitlines()
    findings = []
    # Collect method/function names declared in this file.
    methods = set()
    for line in lines:
        m = re.match(r"\s*(?:private\s+|internal\s+|public\s+|static\s+|@\w+\s+)*func\s+(\w+)", line)
        if m:
            methods.add(m.group(1))
    # Collect local `var`/`let` declarations inside function bodies (indent >= 8).
    for index, line in enumerate(lines, 1):
        m = re.match(r"(\s+)(?:var|let)\s+(\w+)\s*[:=]", line)
        if not m:
            continue
        indent, name = len(m.group(1)), m.group(2)
        if indent < 8 or name not in methods:
            continue
        # Only report when the same body actually calls it as a function.
        for offset in range(index, min(index + 200, len(lines))):
            body = lines[offset]
            if re.search(r"(?<![\w.])" + re.escape(name) + r"\s*\(", body) and "func " not in body:
                findings.append((index, name, offset + 1, body.strip()[:90]))
                break
    return findings

if __name__ == "__main__":
    total = 0
    for path in sys.argv[1:]:
        rows = analyse(path)
        total += len(rows)
        for decl, name, use, snippet in rows:
            print(f"{path}:{decl}: '{name}' shadows a method and is called at line {use}: {snippet}")
    print(f"shadow findings: {total}")
    raise SystemExit(1 if total else 0)
