"""Inventory local source rules without executing JavaScript or contacting publishers.

Usage: python -B -X utf8 scripts/audit_source_capabilities.py --manifest <MANIFEST.json>
       --out <EXTERNAL_REPORT.json> [--core SourceReadSwift/Core]
Only identities, counts, API names and literal-redacted excerpts leave the input files.
Lexical call candidates are not execution coverage or compatibility pass results.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re


RULE_FIELDS = {"searchUrl", "exploreUrl", "loginUrl", "loginUi", "loginCheckJs", "jsLib", "header"}
BRIDGE_CALL = re.compile(r"\b((?:java|source|cookie|cache|book|chapter|android|Packages)(?:\s*\.\s*[A-Za-z_$][\w$]*)+)\s*\(")
BRIDGE_DEFINITION = re.compile(r"\b((?:java|source|cookie|cache|book|chapter)(?:\s*\.\s*[A-Za-z_$][\w$]*)+)\s*=\s*(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)")
ANDROID_PATH = re.compile(r"\b(?:Packages\.)?android(?:\s*\.\s*[A-Za-z_$][\w$]*)+")
TYPE_WRITE = re.compile(r"\bbook\s*\.\s*(?:type\s*=|setType\s*\()\s*(\d+)?")


def fingerprint(value: object) -> str:
    """Hash an exact rule or source identity without changing URL case or fragments."""
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf8")
    return hashlib.sha256(encoded).hexdigest()


def redact_script_literals(script: str) -> str:
    """Erase strings/comments while retaining line positions and code identifiers.

    Template literals are deliberately opaque, including interpolations. This is a
    static inventory, not a JavaScript parser; dynamically generated calls remain unknown.
    """
    chars = list(script)
    position = 0
    while position < len(script):
        start = position
        quote = script[position] if script[position] in "\"'`" else None
        if quote:
            position += 1
            while position < len(script):
                if script[position] == "\\":
                    position += 2
                elif script[position] == quote:
                    position += 1
                    break
                else:
                    position += 1
        elif script.startswith("//", position):
            position = script.find("\n", position)
            if position == -1:
                position = len(script)
        elif script.startswith("/*", position):
            end = script.find("*/", position + 2)
            position = len(script) if end == -1 else end + 2
        else:
            position += 1
            continue
        for index in range(start, min(position, len(script))):
            if chars[index] not in "\r\n":
                chars[index] = " "
    return "".join(chars)


def iter_rule_text(value: object, path: str):
    """Visit structured and stringified rule/form objects, never metadata comments."""
    if isinstance(value, dict):
        for key, item in value.items():
            yield from iter_rule_text(item, f"{path}.{key}")
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from iter_rule_text(item, f"{path}[{index}]")
    elif isinstance(value, str) and value.strip():
        stripped = value.strip()
        if stripped.startswith(("{", "[")):
            try:
                nested = json.loads(stripped)
            except ValueError:
                nested = None
            if isinstance(nested, (dict, list)):
                yield from iter_rule_text(nested, path)
                return
        yield path, value


def rule_texts(source: dict):
    """Enumerate executable rule containers and explicit source-side scripts."""
    for key, value in source.items():
        if key in RULE_FIELDS or key.startswith("rule"):
            yield from iter_rule_text(value, key)


def summarize_rule(source: dict, native_text: str | set[str]) -> dict:
    """Summarize lexical requirements and keep excerpts free of string literals."""
    calls = set()
    definitions = set()
    android_paths = set()
    excerpts = []
    type_writes = []
    for path, script in rule_texts(source):
        masked = redact_script_literals(script)
        calls.update(re.sub(r"\s+", "", match.group(1)) for match in BRIDGE_CALL.finditer(masked))
        definitions.update(re.sub(r"\s+", "", match.group(1)) for match in BRIDGE_DEFINITION.finditer(masked))
        android_paths.update(re.sub(r"\s+", "", match.group()) for match in ANDROID_PATH.finditer(masked))
        for match in TYPE_WRITE.finditer(masked):
            type_writes.append({"field": path, "constant": int(match.group(1)) if match.group(1) else None})
        if path.endswith("imageDecode"):
            excerpts.append({"field": path, "characters": len(script),
                             "form": "js_directive" if script.lstrip().startswith(("@js:", "<js>")) else "plain",
                             "literal_redacted_script": masked,
                             "uses_result_bytes": bool(re.search(r"\bresult(?:\s*\.\s*(?:slice|length|read)\b|\s*\[)", masked)),
                             "uses_source_url": bool(re.search(r"\bsrc\b", masked))})
    unresolved = []
    native_names = set(re.findall(r"[A-Za-z_$][\w$]*", native_text)) if isinstance(native_text, str) else native_text
    if native_names:
        for call in sorted(calls - definitions):
            method = call.rsplit(".", 1)[-1]
            if method not in native_names:
                unresolved.append(call)
    content = source.get("ruleContent") or {}
    if isinstance(content, str):
        try:
            content = json.loads(content)
        except ValueError:
            content = {}
    return {
        "source_key": fingerprint(str(source.get("bookSourceUrl", "")).strip()),
        "rule_key": fingerprint(source),
        "name": str(source.get("bookSourceName", "")),
        "declared_type": source.get("bookSourceType"),
        "has_search": bool(source.get("searchUrl")),
        "has_login_url": bool(source.get("loginUrl")),
        "has_login_ui": bool(source.get("loginUi")),
        "has_login_check": bool(source.get("loginCheckJs")),
        "call_candidates": sorted(calls),
        "authored_bridge_definitions": sorted(definitions),
        "android_paths": sorted(android_paths),
        "not_named_in_native_core": unresolved,
        "image_decode": excerpts,
        "book_type_writes": type_writes,
        "content_fields": sorted(key for key, value in content.items() if value) if isinstance(content, dict) else [],
        "reading_pipeline": "not_executed",
    }


def audit_libraries(inputs: list[Path], native_text: str = "") -> dict:
    """Deduplicate exact definitions separately from source identities and variants."""
    libraries = []
    variants = {}
    identities = defaultdict(set)
    url_names = set()
    total = 0
    native_names = set(re.findall(r"[A-Za-z_$][\w$]*", native_text))
    for number, path in enumerate(inputs, start=1):
        payload = path.read_bytes()
        rows = json.loads(payload.decode("utf-8-sig"))
        if not isinstance(rows, list) or not rows:
            raise ValueError(f"library {number} must be a nonempty array")
        if any(not isinstance(row, dict) for row in rows):
            raise ValueError(f"library {number} contains a nonobject row")
        libraries.append({"library": number, "sha256": hashlib.sha256(payload).hexdigest(),
                          "bytes": len(payload), "records": len(rows),
                          "declared_types": dict(Counter(str(row.get("bookSourceType", "missing")) for row in rows))})
        for index, source in enumerate(rows, start=1):
            total += 1
            identity = str(source.get("bookSourceUrl", "")).strip()
            if not identity:
                raise ValueError(f"library {number} row {index} has no source identity")
            digest = fingerprint(source)
            identities[fingerprint(identity)].add(digest)
            url_names.add((identity, str(source.get("bookSourceName", ""))))
            if digest not in variants:
                variants[digest] = summarize_rule(source, native_names)
                variants[digest]["occurrences"] = []
            variants[digest]["occurrences"].append({"library": number, "row": index})
    rows = list(variants.values())
    call_sources = defaultdict(set)
    for row in rows:
        for call in row["call_candidates"]:
            call_sources[call].add(row["source_key"])
    return {
        "scope": "static local inventory; no rule execution or network requests",
        "limitations": ["Lexical calls are candidates, not confirmed execution paths.",
                        "Template literals and quoted generated JavaScript are opaque.",
                        "An API name found in native source does not prove correct semantics.",
                        "Distinct definitions sharing an identity are preserved, never silently overwritten."],
        "libraries": libraries,
        "records": total,
        "distinct_definitions": len(rows),
        "distinct_source_identities": len(identities),
        "distinct_url_name_pairs": len(url_names),
        "identities_with_definition_variants": sum(len(keys) > 1 for keys in identities.values()),
        "api_identity_counts": {call: len(keys) for call, keys in sorted(call_sources.items())},
        "rows": rows,
    }


def main() -> int:
    """Write a local redacted audit without publishing any original source export."""
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--manifest", type=Path, required=True)
    cli.add_argument("--out", type=Path, required=True)
    cli.add_argument("--core", type=Path)
    args = cli.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8-sig"))
    inputs = [Path(row["path"]) for row in manifest if str(row.get("path", "")).lower().endswith(".json")]
    native_text = ""
    if args.core:
        native_text = "\n".join(path.read_text(encoding="utf-8-sig") for path in args.core.rglob("*.swift"))
    report = audit_libraries(inputs, native_text)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({key: value for key, value in report.items() if key not in {"rows", "api_identity_counts"}}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
