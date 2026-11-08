"""Compare changed Swift syntax with the previous CI input without touching the checkout.

Usage: python -B -X utf8 scripts/check_source_followup.py
This checks parser deltas only; SDK compilation and XCTest still require macOS.
"""
from collections import Counter
from hashlib import sha256
import json
from pathlib import Path
import subprocess

from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[1]
BASE = "2b5e291e1bf284ee6120f404b39ab6aa2a04220c"
BACKUP = Path("F:/SourceReadSwift/project-audit-20261106/source-followup-before")
FILES = [
    "SourceReadSwift/App/AppState.swift",
    "SourceReadSwift/Core/Engine/SourceEngine.swift",
    "SourceReadSwift/Core/Import/SourceImportDownloader.swift",
    "SourceReadSwift/Core/Import/SourcePublisherLinks.swift",
    "SourceReadSwift/Core/Models/BookSource.swift",
    "SourceReadSwift/Core/Rules/RuleExecutionContext.swift",
    "SourceReadSwift/Core/Storage/SourceStore.swift",
    "SourceReadSwift/Core/Storage/SourceVariableStore.swift",
    "SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift",
    "SourceReadSwift/Features/Discover/BookDetailView.swift",
    "SourceReadSwift/Features/Discover/DiscoverView.swift",
    "SourceReadSwift/Features/Search/GlobalSearchView.swift",
    "SourceReadSwift/Features/SourceManager/SourceManagerView.swift",
    "SourceReadSwift/Features/SourceManager/SourcePublisherLinksView.swift",
    "SourceReadSwiftTests/AggregateSourceRegressionTests.swift",
    "SourceReadSwiftTests/SourceImportDownloaderTests.swift",
    "SourceReadSwiftTests/SourcePublisherLinksTests.swift",
    "SourceReadSwiftTests/SourceVariablePersistenceTests.swift",
]


def parse_errors(parser, content):
    errors = Counter()
    pending = [parser.parse(content).root_node]
    while pending:
        node = pending.pop()
        if node.type == "ERROR" or node.is_missing:
            errors[(node.type, content[node.start_byte:node.end_byte].decode("utf-8"))] += 1
        pending.extend(node.children)
    return errors


def main():
    parser = Parser(Language(tree_sitter_swift.language()))
    rows = []
    for relative in FILES:
        current = (ROOT / relative).read_bytes()
        previous = subprocess.run(["git", "show", f"{BASE}:{relative}"], cwd=ROOT, capture_output=True)
        baseline = previous.stdout if previous.returncode == 0 else b""
        if baseline:
            backup = BACKUP / relative
            backup.parent.mkdir(parents=True, exist_ok=True)
            if not backup.exists():
                backup.write_bytes(baseline)
        added = parse_errors(parser, current) - parse_errors(parser, baseline)
        rows.append({"path": relative, "sha256": sha256(current).hexdigest(),
                     "baseline_exists": bool(baseline), "new_parser_errors": sum(added.values()),
                     "error_snippets": [signature[1][:100] for signature in added]})
    report = {"baseline_commit": BASE, "native_compilation": "not_run_on_windows", "files": rows}
    destination = ROOT / "docs/project-audit-20261106/SOURCE-FOLLOWUP-SYNTAX.json"
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    failures = [row for row in rows if row["new_parser_errors"]]
    print(json.dumps({"files": len(rows), "new_parser_errors": sum(row["new_parser_errors"] for row in rows),
                      "failures": failures}, ensure_ascii=False))
    raise SystemExit(bool(failures))


if __name__ == "__main__":
    main()
