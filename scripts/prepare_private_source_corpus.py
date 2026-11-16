"""Pack private source fixtures and decrypt returned reports without publishing plaintext.

Usage (key is canonical base64 of 32 bytes, supplied only through an environment variable):
  python -B -X utf8 scripts/prepare_private_source_corpus.py pack --manifest <INPUT_MANIFEST>
      --output <CORPUS.enc> --key-env PRIVATE_SOURCE_CORPUS_KEY
  python -B -X utf8 scripts/prepare_private_source_corpus.py decrypt-corpus --input <CORPUS.enc>
      --input-sha256 <SHA256> --output-dir <EXTERNAL_DIRECTORY> --key-env PRIVATE_SOURCE_CORPUS_KEY
  python -B -X utf8 scripts/prepare_private_source_corpus.py encrypt-report --input <REPORT.json>
      --input-sha256 <SHA256> --manifest <PUBLIC_MANIFEST> --output <REPORT.enc> --key-env PRIVATE_SOURCE_CORPUS_KEY
  python -B -X utf8 scripts/prepare_private_source_corpus.py decrypt-report --input <REPORT.enc>
      --input-sha256 <SHA256> --manifest <PUBLIC_MANIFEST> --output <EXTERNAL_REPORT.json> --key-env PRIVATE_SOURCE_CORPUS_KEY
  seal-logs / open-logs use --input, --input-sha256 and --output for arbitrary binary log archives.

All outputs are create-only. pack also writes <CORPUS.enc>.manifest.json (identities/counts only).
Original JSON bytes and their array indexes are preserved, including duplicate sources.
Wire: magic[8] + big-endian headerLength[4] + JSON header + nonce[12] + ciphertext + GCM tag[16].
The complete prefix through the JSON header is authenticated as AAD. Plaintext is gzip-compressed.
"""

import argparse
import base64
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import struct
import sys


MAGIC = b"SRPC152\x01"
MAX_HEADER_BYTES = 16 * 1024
MAX_CIPHER_BYTES = 64 * 1024 * 1024
MAX_PLAINTEXT_BYTES = 128 * 1024 * 1024
MAX_SOURCE_BYTES = 32 * 1024 * 1024
MAX_RECORDS = 100_000
MAX_FILES = 100
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    """Reject invalid input with a value-free error suitable for CI logs."""
    if not condition:
        raise ValueError(message)


def sha256(payload: bytes) -> str:
    """Return the digest of the exact original bytes."""
    return hashlib.sha256(payload).hexdigest()


def positive_count(value: object, maximum: int, label: str) -> int:
    """Accept bounded integers, excluding bool values accepted by Python's int type."""
    require(type(value) is int and 0 < value <= maximum, f"Invalid {label}")
    return value


def require_sha(value: object) -> str:
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None, "Invalid SHA-256")
    return value


def read_bounded(path: Path, maximum: int) -> bytes:
    """Bound reads even if the file grows between stat and read."""
    require(path.is_file() and path.stat().st_size <= maximum, "Input is absent or exceeds its byte limit")
    with path.open("rb") as stream:
        payload = stream.read(maximum + 1)
    require(len(payload) <= maximum, "Input exceeds its byte limit")
    return payload


def reject_constant(_: str) -> None:
    raise ValueError("Non-finite JSON number")


def decode_json(payload: bytes) -> object:
    """Decode UTF-8 JSON without echoing invalid source text in an exception."""
    try:
        return json.loads(payload.decode("utf-8-sig"), parse_constant=reject_constant)
    except (ValueError, UnicodeError, RecursionError):
        raise ValueError("Input is not valid finite UTF-8 JSON") from None


def encode_json(document: object) -> bytes:
    return json.dumps(document, ensure_ascii=True, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf8")


def source_rows(payload: bytes) -> list[dict]:
    rows = decode_json(payload)
    require(isinstance(rows, list) and all(isinstance(row, dict) for row in rows), "Source JSON must be an array of objects")
    positive_count(len(rows), MAX_RECORDS, "source record count")
    return rows


def read_key(variable: str) -> bytes:
    """Read a 256-bit key from the environment; never log or persist it."""
    require(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", variable) is not None, "Invalid key environment variable name")
    try:
        key = base64.b64decode(os.environ.get(variable, ""), validate=True)
    except (ValueError, UnicodeError):
        raise ValueError("Key environment variable must contain canonical base64 for 32 bytes") from None
    require(len(key) == 32 and base64.b64encode(key).decode() == os.environ.get(variable),
            "Key environment variable must contain canonical base64 for 32 bytes")
    return key


def validate_manifest(document: object, expected_files: int, expected_records: int) -> dict:
    require(isinstance(document, dict) and document.get("schemaVersion") == 1, "Invalid corpus manifest version")
    files = document.get("files")
    require(isinstance(files, list) and len(files) == expected_files, "Manifest file count mismatch")
    require(document.get("totalRecords") == expected_records, "Manifest record count mismatch")
    identities = set()
    total = 0
    for ordinal, entry in enumerate(files, 1):
        require(isinstance(entry, dict), "Invalid manifest file entry")
        identifier = f"sources-{ordinal:02d}"
        require(entry.get("fileId") == identifier and identifier not in identities, "Manifest file identity/order mismatch")
        require(entry.get("relativePath") == identifier + ".json", "Unsafe manifest relative path")
        require_sha(entry.get("sha256"))
        positive_count(entry.get("bytes"), MAX_SOURCE_BYTES, "source byte count")
        total += positive_count(entry.get("expectedCount"), MAX_RECORDS, "source record count")
        identities.add(identifier)
    require(total == expected_records, "Manifest per-file counts do not match totalRecords")
    return document


def build_bundle(manifest_path: Path, expected_files: int, expected_records: int) -> tuple[bytes, dict]:
    """Verify the local inventory and preserve every original JSON byte and occurrence."""
    inventory = decode_json(read_bounded(manifest_path, MAX_SOURCE_BYTES))
    require(isinstance(inventory, list), "Input inventory must be an array")
    selected = [entry for entry in inventory if isinstance(entry, dict) and entry.get("json_type") == "list"]
    require(len(selected) == expected_files, "Input inventory JSON file count mismatch")
    manifest_files, payload_files = [], []
    for ordinal, entry in enumerate(selected, 1):
        identifier = f"sources-{ordinal:02d}"
        require(isinstance(entry.get("path"), str) and entry.get("exists") is True, "Invalid inventory source path")
        expected_size = positive_count(entry.get("bytes"), MAX_SOURCE_BYTES, "inventory byte count")
        expected_sha = require_sha(entry.get("sha256"))
        expected_count = positive_count(entry.get("count"), MAX_RECORDS, "inventory record count")
        raw = read_bounded(Path(entry["path"]), MAX_SOURCE_BYTES)
        require(len(raw) == expected_size and sha256(raw) == expected_sha, "Original source bytes/SHA-256 differ from inventory")
        require(len(source_rows(raw)) == expected_count, "Original source record count differs from inventory")
        manifest_files.append({"fileId": identifier, "relativePath": identifier + ".json", "sha256": expected_sha,
                               "bytes": len(raw), "expectedCount": expected_count})
        payload_files.append({"fileId": identifier, "contentBase64": base64.b64encode(raw).decode("ascii")})
    manifest = {"schemaVersion": 1, "totalRecords": expected_records, "files": manifest_files}
    validate_manifest(manifest, expected_files, expected_records)
    bundle = encode_json({"schemaVersion": 1, "manifest": manifest, "files": payload_files})
    require(len(bundle) <= MAX_PLAINTEXT_BYTES, "Corpus bundle exceeds plaintext limit")
    return bundle, manifest


def validate_bundle(payload: bytes, expected_files: int, expected_records: int) -> tuple[dict, list[bytes]]:
    document = decode_json(payload)
    require(isinstance(document, dict) and document.get("schemaVersion") == 1, "Invalid bundle version")
    manifest = validate_manifest(document.get("manifest"), expected_files, expected_records)
    files = document.get("files")
    require(isinstance(files, list) and len(files) == expected_files, "Bundle file count mismatch")
    originals = []
    for metadata, entry in zip(manifest["files"], files):
        require(isinstance(entry, dict) and entry.get("fileId") == metadata["fileId"], "Bundle file identity/order mismatch")
        try:
            encoded = entry["contentBase64"]
            require(isinstance(encoded, str), "Invalid original byte encoding")
            raw = base64.b64decode(encoded, validate=True)
        except (KeyError, ValueError, UnicodeError):
            raise ValueError("Invalid original byte encoding") from None
        require(len(raw) == metadata["bytes"] and sha256(raw) == metadata["sha256"], "Bundled source bytes/SHA-256 mismatch")
        require(len(source_rows(raw)) == metadata["expectedCount"], "Bundled source count mismatch")
        originals.append(raw)
    return manifest, originals


def validate_report(payload: bytes, manifest: dict) -> None:
    report = decode_json(payload)
    require(isinstance(report, dict) and report.get("schemaVersion") == 1, "Invalid report version")
    require(report.get("mode") in ("inspect", "live"), "Invalid report mode")
    rows = report.get("rows")
    count = manifest["totalRecords"]
    require(report.get("totalRecords") == count and isinstance(rows, list) and len(rows) == count, "Report row count mismatch")
    selected = report.get("selectedRecords")
    require(type(selected) is int and 0 <= selected <= count, "Invalid report selectedRecords")
    expected = {(entry["fileId"], entry["sha256"], index)
                for entry in manifest["files"] for index in range(entry["expectedCount"])}
    actual = set()
    for row in rows:
        require(isinstance(row, dict) and type(row.get("index")) is int, "Invalid report row identity")
        identity = (row.get("fileId"), row.get("fileSHA"), row["index"])
        require(all(isinstance(part, str) for part in identity[:2]), "Invalid report row identity")
        require(identity in expected and identity not in actual, "Unknown or repeated report row identity")
        require(row.get("status") in ("notRun", "inspected", "passed", "failed", "requiresLogin", "mediaExtracted"), "Invalid report row status")
        actual.add(identity)
    require(actual == expected, "Report omitted original source occurrences")


def seal(payload: bytes, key: bytes, purpose: str, file_count: int, record_count: int) -> bytes:
    """Encrypt gzip bytes with a fresh GCM nonce and an authenticated size/hash/count header."""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    require(purpose in ("corpus", "report", "logs") and len(key) == 32, "Invalid encryption parameters")
    require(0 < len(payload) <= MAX_PLAINTEXT_BYTES, "Invalid plaintext byte count")
    positive_count(file_count, MAX_FILES, "file count")
    positive_count(record_count, MAX_RECORDS, "record count")
    compressed = gzip.compress(payload, mtime=0)
    header = encode_json({"schemaVersion": 1, "purpose": purpose, "compression": "gzip",
        "plaintextBytes": len(payload), "plaintextSHA256": sha256(payload), "compressedBytes": len(compressed),
        "fileCount": file_count, "recordCount": record_count})
    prefix = MAGIC + struct.pack(">I", len(header)) + header
    nonce = os.urandom(12)
    encrypted = prefix + nonce + AESGCM(key).encrypt(nonce, compressed, prefix)
    require(len(encrypted) <= MAX_CIPHER_BYTES, "Encrypted package exceeds byte limit")
    return encrypted


def unseal(encrypted: bytes, key: bytes, purpose: str, expected_files: int, expected_records: int) -> bytes:
    from cryptography.exceptions import InvalidTag
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    require(len(key) == 32 and 40 <= len(encrypted) <= MAX_CIPHER_BYTES and encrypted[:8] == MAGIC, "Invalid encrypted package")
    header_length = struct.unpack(">I", encrypted[8:12])[0]
    require(0 < header_length <= MAX_HEADER_BYTES and len(encrypted) >= 12 + header_length + 28, "Invalid encrypted header length")
    prefix = encrypted[:12 + header_length]
    header = decode_json(prefix[12:])
    require(isinstance(header, dict) and header.get("schemaVersion") == 1 and header.get("purpose") == purpose
            and header.get("compression") == "gzip", "Encrypted package purpose/version mismatch")
    plain_size = positive_count(header.get("plaintextBytes"), MAX_PLAINTEXT_BYTES, "plaintext byte count")
    compressed_size = positive_count(header.get("compressedBytes"), MAX_CIPHER_BYTES, "compressed byte count")
    require_sha(header.get("plaintextSHA256"))
    require(header.get("fileCount") == expected_files and header.get("recordCount") == expected_records, "Encrypted package count mismatch")
    require(len(encrypted) == len(prefix) + 12 + compressed_size + 16, "Encrypted package size mismatch")
    try:
        compressed = AESGCM(key).decrypt(encrypted[len(prefix):len(prefix) + 12], encrypted[len(prefix) + 12:], prefix)
    except InvalidTag:
        raise ValueError("Encrypted package authentication failed") from None
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as stream:
            payload = stream.read(plain_size + 1)
    except (OSError, EOFError):
        raise ValueError("Invalid gzip payload") from None
    require(len(payload) == plain_size and sha256(payload) == header["plaintextSHA256"], "Plaintext bytes/SHA-256 mismatch")
    return payload


def require_external_plaintext(path: Path) -> None:
    require(not path.resolve().is_relative_to(REPOSITORY_ROOT), "Plaintext output must be outside the repository")


def write_new(path: Path, payload: bytes) -> None:
    """Never overwrite an original file, existing package, or prior report."""
    require(not path.exists() and not path.is_symlink(), "Output already exists")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(payload)
    require(sha256(read_bounded(path, len(payload))) == sha256(payload), "Output SHA-256 verification failed")


def extract_bundle(payload: bytes, destination: Path, expected_files: int, expected_records: int) -> dict:
    require_external_plaintext(destination)
    manifest, originals = validate_bundle(payload, expected_files, expected_records)
    require(not destination.exists() and not destination.is_symlink(), "Output directory already exists")
    destination.mkdir(parents=True, exist_ok=False)
    for entry, raw in zip(manifest["files"], originals):
        write_new(destination / entry["relativePath"], raw)
    write_new(destination / "manifest.json", encode_json(manifest))
    return manifest


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("pack", "decrypt-corpus", "encrypt-report", "decrypt-report", "seal-logs", "open-logs"))
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--input", type=Path)
    parser.add_argument("--input-sha256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--key-env", default="PRIVATE_SOURCE_CORPUS_KEY")
    parser.add_argument("--expected-files", type=int, default=5)
    parser.add_argument("--expected-records", type=int, default=1128)
    options = parser.parse_args(arguments)
    try:
        positive_count(options.expected_files, MAX_FILES, "expected file count")
        positive_count(options.expected_records, MAX_RECORDS, "expected record count")
        key = read_key(options.key_env)
        if options.command == "pack":
            require(options.manifest is not None and options.output is not None, "pack requires --manifest and --output")
            payload, manifest = build_bundle(options.manifest, options.expected_files, options.expected_records)
            output = seal(payload, key, "corpus", options.expected_files, options.expected_records)
            public_manifest = Path(str(options.output) + ".manifest.json")
            require(not public_manifest.exists(), "Public manifest output already exists")
            write_new(options.output, output)
            write_new(public_manifest, encode_json(manifest))
        else:
            require(options.input is not None, "Command requires --input")
            require_sha(options.input_sha256)
            original = read_bounded(options.input, MAX_PLAINTEXT_BYTES if options.command in ("encrypt-report", "seal-logs") else MAX_CIPHER_BYTES)
            require(sha256(original) == options.input_sha256, "Input SHA-256 mismatch")
            if options.command == "decrypt-corpus":
                require(options.output_dir is not None, "decrypt-corpus requires --output-dir")
                output = unseal(original, key, "corpus", options.expected_files, options.expected_records)
                extract_bundle(output, options.output_dir, options.expected_files, options.expected_records)
            elif options.command in ("seal-logs", "open-logs"):
                require(options.output is not None, "Log command requires --output")
                if options.command == "seal-logs":
                    output = seal(original, key, "logs", options.expected_files, options.expected_records)
                else:
                    require_external_plaintext(options.output)
                    output = unseal(original, key, "logs", options.expected_files, options.expected_records)
                write_new(options.output, output)
            else:
                require(options.manifest is not None and options.output is not None, "Report command requires --manifest and --output")
                manifest = validate_manifest(decode_json(read_bounded(options.manifest, MAX_HEADER_BYTES)), options.expected_files, options.expected_records)
                if options.command == "encrypt-report":
                    validate_report(original, manifest)
                    output = seal(original, key, "report", options.expected_files, options.expected_records)
                else:
                    require_external_plaintext(options.output)
                    output = unseal(original, key, "report", options.expected_files, options.expected_records)
                    validate_report(output, manifest)
                write_new(options.output, output)
        print(json.dumps({"command": options.command, "bytes": len(output), "sha256": sha256(output),
                          "files": options.expected_files, "records": options.expected_records}, sort_keys=True))
        return 0
    except (ValueError, OSError, ImportError) as error:
        message = str(error) if isinstance(error, ValueError) else "File operation or required cryptography module unavailable"
        print("Private corpus operation failed: " + message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
