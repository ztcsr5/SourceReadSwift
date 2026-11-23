"""Count original source definitions and dialect signals without executing imported rules."""
import argparse
from collections import Counter
from pathlib import Path
import re
from urllib.parse import urlsplit

from prepare_private_source_corpus import (
    MAX_FILES, MAX_PLAINTEXT_BYTES, MAX_RECORDS, MAX_SOURCE_BYTES, decode_json, encode_json, read_bounded, sha256, source_rows,
)

RULE_GROUPS = ("ruleSearch", "ruleExplore", "ruleBookInfo", "ruleToc", "ruleContent")
SCRIPT_MARK = re.compile(r"(?i)@js:|<js\b|\bjava\.|\bPackages\.|\bimportPackage\(|\borg\.jsoup\b")
RULE_SIGNALS = {
    "xpath": re.compile(r"(?i)@xpath:|(?:^|\s)//(?:[A-Za-z_*]|@)"),
    "jsonpath": re.compile(r"(?i)@json:|\$\.[\w\[]|\$\["),
    "image-output": re.compile(r"(?i)\b(?:img|imageUrls|imgList|imageList|picList)\b"),
    "media-output": re.compile(r"(?i)\b(?:m3u8|mp4|mp3|flac|mpd|videoUrl|audioUrl|playUrl|streamUrl)\b"),
    "webview": re.compile(r"(?i)\b(?:webView|webJs)\b"),
    "android-bridge": re.compile(r"(?i)\b(?:Packages\.|android\.|org\.jsoup|importPackage\()"),
}


def has_text(value: object) -> bool:
    """Accept a defined, nonblank string rather than a truthy fragment of another type."""
    return isinstance(value, str) and bool(value.strip())


def address_shape(value: object) -> str:
    """Describe address syntax without exporting domains, user info, or query values."""
    if not has_text(value):
        return "missing"
    try:
        parsed = urlsplit(value.strip())
        if parsed.scheme.lower() in ("http", "https") and parsed.hostname:
            return "http"
    except ValueError:
        return "invalid"
    return "other"


def inspect_definition(source: dict) -> dict:
    """Return non-executing coverage signals; none constitute runtime passes."""
    declared = source.get("bookSourceType")
    try:
        normalized_type = int(declared) if type(declared) in (int, str) else None
    except ValueError:
        normalized_type = None
    group_shapes = Counter()
    for group in RULE_GROUPS:
        if group in source and source[group] is not None:
            group_shapes[f"{group}:{type(source[group]).__name__}"] += 1
    rules = [source.get(key) for key in
             (*RULE_GROUPS, "jsLib", "searchUrl", "exploreUrl", "header", "loginCheckJs", "customConfig")]
    rule_text = encode_json(rules).decode("ascii")
    return {
        "declaredType": str(normalized_type) if normalized_type is not None else "absent-or-invalid",
        "sourceAddress": address_shape(source.get("bookSourceUrl")),
        "search": has_text(source.get("searchUrl")),
        "explore": has_text(source.get("exploreUrl")),
        "declaresLogin": has_text(source.get("loginUrl")) or has_text(source.get("loginUi")),
        "hasScript": has_text(source.get("jsLib")) or bool(SCRIPT_MARK.search(rule_text)),
        "groups": dict(group_shapes),
        "signals": [name for name, pattern in RULE_SIGNALS.items() if pattern.search(rule_text)],
    }


def inspect_sources(paths: list[Path]) -> dict:
    """Group canonical duplicate rows but preserve every file/index occurrence."""
    if not 1 <= len(paths) <= MAX_FILES:
        raise ValueError("Input file count is outside the private corpus limit")
    files = []
    total_rows = 0
    definitions: dict[str, dict] = {}
    for number, path in enumerate(paths, 1):
        batch = f"sources-{number:02d}"
        payload = read_bounded(path, MAX_SOURCE_BYTES)
        rows = source_rows(payload)
        total_rows += len(rows)
        if total_rows > MAX_RECORDS:
            raise ValueError("Combined source definitions exceed the inventory limit")
        keys = set()
        for index, row in enumerate(rows):
            key = sha256(encode_json(row))
            if key not in definitions:
                definitions[key] = {**inspect_definition(row), "occurrences": [], "endToEnd": "notRun"}
            definitions[key]["occurrences"].append([batch, index])
            keys.add(key)
        files.append({"id": batch, "bytes": len(payload), "sha256": sha256(payload),
                      "rows": len(rows), "uniqueRows": len(keys),
                      "declaredTypes": dict(Counter(definitions[key]["declaredType"] for key in sorted(keys)))})
    totals = list(definitions.values())
    return {
        "files": files,
        "uniqueFiles": len({file["sha256"] for file in files}),
        "totalRows": total_rows,
        "uniqueDefinitions": len(totals),
        "minimumPasses": (9 * len(totals) + 9) // 10,
        "endToEndPassed": sum(row["endToEnd"] == "passed" for row in totals),
        "releaseGatePassed": False,
        "declaredTypes": dict(Counter(row["declaredType"] for row in totals)),
        "sourceAddress": dict(Counter(row["sourceAddress"] for row in totals)),
        "ruleGroupShapes": dict(sum((Counter(row["groups"]) for row in totals), Counter())),
        "search": sum(row["search"] for row in totals),
        "explore": sum(row["explore"] for row in totals),
        "declaresLogin": sum(row["declaresLogin"] for row in totals),
        "hasScript": sum(row["hasScript"] for row in totals),
        "signals": dict(Counter(signal for row in totals for signal in row["signals"])),
        "definitions": definitions,
    }


def verifies_content(row: dict) -> bool:
    """A live pass needs the real final output, not a structure scan or stream URL."""
    if row.get("status") != "passed":
        return False
    stages = {item.get("stage") for item in row.get("stages", [])
              if isinstance(item, dict) and item.get("status") == "passed"}
    if not {"search", "detail", "toc", "content"} <= stages:
        return False
    kind = row.get("resolvedMediaKind")
    if kind in (1, 3):
        return row.get("playbackVerified") is True and "media-playback" in stages
    if kind == 2:
        images = row.get("imageSampleDecoded")
        return isinstance(images, list) and len(images) > 0 and all(item is True for item in images)
    observation = row.get("contentObservation")
    return (kind == 0 and isinstance(observation, dict) and type(observation.get("bytes")) is int
            and observation["bytes"] > 0 and observation.get("matchesContentRuleLiterally") is False)


def merge_native_passes(inventory: dict, receipts: list[Path], revision: str) -> None:
    """Merge same-revision live shards by original file hash and index; do not count duplicates twice."""
    if re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        raise ValueError("A full candidate Git SHA is required")
    shas = {file["id"]: file["sha256"] for file in inventory["files"]}
    occurrences = {(file_id, index): definition for definition in inventory["definitions"].values()
                   for file_id, index in definition["occurrences"]}
    for receipt in receipts:
        report = decode_json(read_bounded(receipt, MAX_PLAINTEXT_BYTES))
        if not isinstance(report, dict) or report.get("revision") != revision or report.get("mode") != "live":
            raise ValueError("Native report does not attest live evidence for the candidate revision")
        rows = report.get("rows")
        if not isinstance(rows, list) or len(rows) != len(occurrences):
            raise ValueError("Native report is missing original source occurrences")
        seen = set()
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("fileId"), str) or type(row.get("index")) is not int:
                raise ValueError("Invalid native report row identity")
            identity = row["fileId"], row["index"]
            if identity not in occurrences or identity in seen or row.get("fileSHA") != shas[identity[0]]:
                raise ValueError("Native report identities do not match inventory")
            seen.add(identity)
            if verifies_content(row):
                definition = occurrences[identity]
                definition["endToEnd"] = "passed"
                definition["verifiedKind"] = row["resolvedMediaKind"]
    passes = [definition for definition in inventory["definitions"].values() if definition["endToEnd"] == "passed"]
    inventory["candidateRevision"] = revision
    inventory["endToEndPassed"] = len(passes)
    inventory["endToEndPassedByKind"] = dict(Counter(str(row["verifiedKind"]) for row in passes))
    inventory["releaseGatePassed"] = len(passes) >= inventory["minimumPasses"]


def stage_native_inputs(paths: list[Path], report: dict, directory: Path) -> None:
    """Create a private, byte-for-byte replay directory only when explicitly requested."""
    directory.mkdir()
    files = []
    for source, counted in zip(paths, report["files"], strict=True):
        payload = read_bounded(source, MAX_SOURCE_BYTES)
        if sha256(payload) != counted["sha256"]:
            raise ValueError(f"Source changed after inventory: {counted['id']}")
        filename = counted["id"] + ".json"
        (directory / filename).write_bytes(payload)
        files.append({"fileId": counted["id"], "relativePath": filename, "bytes": counted["bytes"],
                      "expectedCount": counted["rows"], "sha256": counted["sha256"]})
    manifest = {"schemaVersion": 1, "totalRecords": report["totalRows"], "files": files}
    (directory / "manifest.json").write_bytes(encode_json(manifest) + b"\n")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("sources", type=Path, nargs="+")
    cli.add_argument("--output", required=True, type=Path)
    cli.add_argument("--stage-native-inputs", type=Path, help="New private directory outside the checkout")
    cli.add_argument("--native-report", type=Path, nargs="+", help="Private live reports for the exact candidate")
    cli.add_argument("--revision", help="Full Git SHA encoded in every native report")
    args = cli.parse_args()
    report = inspect_sources(args.sources)
    if args.native_report:
        if args.revision is None:
            cli.error("Use --revision with --native-report")
        merge_native_passes(report, args.native_report, args.revision)
    with args.output.open("xb") as output:
        output.write(encode_json(report) + b"\n")
    if args.stage_native_inputs is not None:
        target = args.stage_native_inputs.resolve()
        repository = Path(__file__).resolve().parents[1]
        if target.is_relative_to(repository):
            cli.error("Keep original source files outside the checkout")
        stage_native_inputs(args.sources, report, target)
    print(encode_json({key: value for key, value in report.items() if key != "definitions"}).decode("ascii"))
