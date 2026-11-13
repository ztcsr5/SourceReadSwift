"""Check changed Swift parser diagnostics against a known native-build snapshot.

Usage: python -B -X utf8 scripts/audit_current_swift_syntax.py <BASE_SHA>
This is a syntax comparison only, not iOS SDK type checking or runtime testing.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

from tree_sitter import Language, Parser
import tree_sitter_swift

from verify_reader_quality import ROOT, select_reader_paths


def diagnostics(parser, source):
    found = Counter()
    pending = [parser.parse(source).root_node]
    while pending:
        node = pending.pop()
        if node.type == "ERROR" or node.is_missing:
            found[(node.type, source[node.start_byte:node.end_byte].decode("utf8"))] += 1
        pending.extend(node.children)
    return found


def main():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument("baseline")
    baseline = arguments.parse_args().baseline
    changed = subprocess.check_output(["git", "diff", "--name-only", "--diff-filter=ACMRT", baseline], cwd=ROOT).decode("utf8").splitlines()
    changed += subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard",
                                       "SourceReadSwift", "SourceReadSwiftTests", "SourceReadSwiftUITests"],
                                      cwd=ROOT).decode("utf8").splitlines()
    parser = Parser(Language(tree_sitter_swift.language()))
    rows = []
    for relative in select_reader_paths(changed):
        if not relative.endswith(".swift"):
            continue
        source = (ROOT / relative).read_bytes()
        previous = subprocess.run(["git", "show", f"{baseline}:{relative}"], cwd=ROOT, capture_output=True)
        if previous.returncode == 0 and source.replace(b"\r\n", b"\n") == previous.stdout.replace(b"\r\n", b"\n"):
            continue
        added = diagnostics(parser, source) - diagnostics(parser, previous.stdout)
        rows.append({"path": relative, "sha256": hashlib.sha256(source).hexdigest(),
                     "new_parser_errors": sum(added.values()),
                     "snippets": [entry[1][:120] for entry in added]})
    destination = ROOT / "docs/project-audit-20261106/CURRENT-SYNTAX.json"
    destination.write_text(json.dumps({"baseline": baseline, "files": rows}, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf8")
    failures = [row for row in rows if row["new_parser_errors"]]
    print(json.dumps({"files": len(rows), "failures": failures, "report": str(destination)}, ensure_ascii=False))
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
