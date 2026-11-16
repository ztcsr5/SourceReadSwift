#!/usr/bin/env swift
// Uses macOS CryptoKit and /usr/bin/gzip; no package installation or network access.
// Usage: swift scripts/private_corpus_cipher.swift decrypt-corpus --input <CORPUS.enc>
//   --input-sha256 <SHA256> --output-dir <EXTERNAL_DIR> --key-env PRIVATE_SOURCE_CORPUS_KEY
// Usage: swift scripts/private_corpus_cipher.swift encrypt-report --input <REPORT.json>
//   --input-sha256 <SHA256> --manifest <EXTERNAL_DIR/manifest.json> --output <REPORT.enc>
// Usage: swift scripts/private_corpus_cipher.swift seal-logs --input <LOGS.tar.gz>
//   --input-sha256 <SHA256> --output <LOGS.enc>
// Also supports decrypt-report and open-logs. Defaults: 5 files, 1128 source occurrences.
// Key environment value: canonical standard base64 of 32 bytes, with no newline.
// Python counterpart defines the authenticated binary wire format. Never prints plaintext or keys.

import Foundation
import CoreFoundation
import CryptoKit
import Darwin

enum CorpusFailure: Error { case invalid(String) }
let magic = Data([0x53, 0x52, 0x50, 0x43, 0x31, 0x35, 0x32, 0x01])
let maximumHeader = 16 * 1024
let maximumCipher = 64 * 1024 * 1024
let maximumPlaintext = 128 * 1024 * 1024
let maximumSource = 32 * 1024 * 1024

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CorpusFailure.invalid(message) }
}

func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

func readBounded(_ path: URL, maximum: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: path)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: maximum + 1) ?? Data()
    try require(bytes.count <= maximum, "Input exceeds byte limit")
    return bytes
}

func decodeJSON(_ bytes: Data) throws -> Any {
    do { return try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) }
    catch { throw CorpusFailure.invalid("Input is not valid JSON") }
}

func encodeJSON(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

func integer(_ value: Any?, maximum: Int, allowsZero: Bool = false) throws -> Int {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite,
          number.doubleValue.rounded(.towardZero) == number.doubleValue,
          number.doubleValue >= (allowsZero ? 0 : 1), number.doubleValue <= Double(maximum) else {
        throw CorpusFailure.invalid("Invalid bounded integer")
    }
    return number.intValue
}

func validSHA(_ value: Any?) throws -> String {
    guard let value = value as? String,
          value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
        throw CorpusFailure.invalid("Invalid SHA-256")
    }
    return value
}

func loadKey(_ variable: String) throws -> SymmetricKey {
    try require(variable.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil,
                "Invalid key environment variable name")
    guard let text = ProcessInfo.processInfo.environment[variable], let bytes = Data(base64Encoded: text),
          bytes.count == 32, bytes.base64EncodedString() == text else {
        throw CorpusFailure.invalid("Key environment variable must contain canonical base64 for 32 bytes")
    }
    return SymmetricKey(data: bytes)
}

struct CorpusFile {
    let fileId: String
    let relativePath: String
    let sha256: String
    let bytes: Int
    let expectedCount: Int
}

func validateManifest(_ value: Any, expectedFiles: Int, expectedRecords: Int) throws -> [CorpusFile] {
    guard let manifest = value as? [String: Any], let files = manifest["files"] as? [[String: Any]] else {
        throw CorpusFailure.invalid("Invalid corpus manifest")
    }
    try require(try integer(manifest["schemaVersion"], maximum: 1) == 1, "Invalid corpus manifest version")
    try require(files.count == expectedFiles, "Manifest file count mismatch")
    try require(try integer(manifest["totalRecords"], maximum: 100_000) == expectedRecords, "Manifest record count mismatch")
    var verified: [CorpusFile] = []
    for (ordinal, entry) in files.enumerated() {
        let identifier = String(format: "sources-%02d", ordinal + 1)
        try require(entry["fileId"] as? String == identifier, "Manifest file identity/order mismatch")
        try require(entry["relativePath"] as? String == identifier + ".json", "Unsafe manifest relative path")
        verified.append(CorpusFile(fileId: identifier, relativePath: identifier + ".json",
            sha256: try validSHA(entry["sha256"]), bytes: try integer(entry["bytes"], maximum: maximumSource),
            expectedCount: try integer(entry["expectedCount"], maximum: 100_000)))
    }
    try require(verified.reduce(0) { $0 + $1.expectedCount } == expectedRecords, "Manifest per-file counts mismatch")
    return verified
}

func requireExternalPlaintext(_ destination: URL) throws {
    let script = URL(fileURLWithPath: #filePath).standardizedFileURL
    let repository = script.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath().path
    let target = destination.standardizedFileURL.resolvingSymlinksInPath().path
    try require(target != repository && !target.hasPrefix(repository + "/"), "Plaintext output must be outside the repository")
}

func writeNew(_ destination: URL, bytes: Data) throws {
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let descriptor = destination.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, 0o600) }
    try require(descriptor >= 0, "Cannot create output; it may already exist")
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    try handle.write(contentsOf: bytes)
    try handle.close()
    try require(digest(try readBounded(destination, maximum: bytes.count)) == digest(bytes), "Output SHA-256 verification failed")
}

func gzipBytes(_ bytes: Data, decompress: Bool, maximum: Int) throws -> Data {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("source-cipher-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("input")
    try writeNew(input, bytes: bytes)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
    process.environment = ["LANG": "C", "LC_ALL": "C"]
    process.arguments = decompress ? ["-d", "-c", input.path] : ["-n", "-c", input.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    defer { if process.isRunning { process.terminate() } }
    var output = Data()
    while let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
        try require(output.count + chunk.count <= maximum, "gzip output exceeds declared byte limit")
        output.append(chunk)
    }
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "gzip operation failed")
    return output
}

func seal(_ plaintext: Data, key: SymmetricKey, purpose: String, counts: (files: Int, records: Int)) throws -> Data {
    try require(!plaintext.isEmpty && plaintext.count <= maximumPlaintext, "Invalid plaintext byte count")
    let compressed = try gzipBytes(plaintext, decompress: false, maximum: maximumCipher)
    let header = try encodeJSON(["schemaVersion": 1, "purpose": purpose, "compression": "gzip",
        "plaintextBytes": plaintext.count, "plaintextSHA256": digest(plaintext), "compressedBytes": compressed.count,
        "fileCount": counts.files, "recordCount": counts.records])
    let size = UInt32(header.count)
    var prefix = magic
    prefix.append(contentsOf: [UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)])
    prefix.append(header)
    let sealed = try AES.GCM.seal(compressed, using: key, authenticating: prefix)
    guard let combined = sealed.combined else { throw CorpusFailure.invalid("Missing AES-GCM combined representation") }
    prefix.append(combined)
    try require(prefix.count <= maximumCipher, "Encrypted package exceeds byte limit")
    return prefix
}

func unseal(_ encrypted: Data, key: SymmetricKey, purpose: String, counts: (files: Int, records: Int)) throws -> Data {
    try require(encrypted.count >= 40 && encrypted.count <= maximumCipher && encrypted.prefix(8) == magic,
                "Invalid encrypted package")
    let headerLength = encrypted[8..<12].reduce(0) { ($0 << 8) | Int($1) }
    try require(headerLength > 0 && headerLength <= maximumHeader && encrypted.count >= 12 + headerLength + 28,
                "Invalid encrypted header length")
    let prefix = encrypted.prefix(12 + headerLength)
    guard let header = try decodeJSON(Data(prefix.dropFirst(12))) as? [String: Any] else {
        throw CorpusFailure.invalid("Invalid encrypted header")
    }
    try require(try integer(header["schemaVersion"], maximum: 1) == 1, "Invalid encrypted version")
    try require(header["purpose"] as? String == purpose && header["compression"] as? String == "gzip",
                "Encrypted package purpose mismatch")
    let plainSize = try integer(header["plaintextBytes"], maximum: maximumPlaintext)
    let compressedSize = try integer(header["compressedBytes"], maximum: maximumCipher)
    let expectedSHA = try validSHA(header["plaintextSHA256"])
    try require(try integer(header["fileCount"], maximum: 100) == counts.files, "Encrypted file count mismatch")
    try require(try integer(header["recordCount"], maximum: 100_000) == counts.records, "Encrypted record count mismatch")
    try require(encrypted.count == prefix.count + 12 + compressedSize + 16, "Encrypted package size mismatch")
    let box = try AES.GCM.SealedBox(combined: encrypted.dropFirst(prefix.count))
    let compressed: Data
    do { compressed = try AES.GCM.open(box, using: key, authenticating: prefix) }
    catch { throw CorpusFailure.invalid("Encrypted package authentication failed") }
    let plaintext = try gzipBytes(compressed, decompress: true, maximum: plainSize)
    try require(plaintext.count == plainSize && digest(plaintext) == expectedSHA, "Plaintext bytes/SHA-256 mismatch")
    return plaintext
}

func extractCorpus(_ payload: Data, destination: URL, counts: (files: Int, records: Int)) throws {
    try requireExternalPlaintext(destination)
    guard let bundle = try decodeJSON(payload) as? [String: Any], let manifest = bundle["manifest"],
          let files = bundle["files"] as? [[String: Any]] else { throw CorpusFailure.invalid("Invalid corpus bundle") }
    try require(try integer(bundle["schemaVersion"], maximum: 1) == 1, "Invalid bundle version")
    let metadata = try validateManifest(manifest, expectedFiles: counts.files, expectedRecords: counts.records)
    try require(files.count == counts.files, "Bundle file count mismatch")
    var originals: [Data] = []
    for (entry, file) in zip(metadata, files) {
        try require(file["fileId"] as? String == entry.fileId, "Bundle identity/order mismatch")
        guard let encoded = file["contentBase64"] as? String, let raw = Data(base64Encoded: encoded),
              raw.count == entry.bytes, digest(raw) == entry.sha256 else {
            throw CorpusFailure.invalid("Bundled source bytes/SHA-256 mismatch")
        }
        guard let rows = try decodeJSON(raw) as? [[String: Any]] else { throw CorpusFailure.invalid("Source must be a JSON object array") }
        try require(rows.count == entry.expectedCount, "Bundled source record count mismatch")
        originals.append(raw)
    }
    try require(!FileManager.default.fileExists(atPath: destination.path), "Output directory already exists")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    for (entry, raw) in zip(metadata, originals) { try writeNew(destination.appendingPathComponent(entry.relativePath), bytes: raw) }
    try writeNew(destination.appendingPathComponent("manifest.json"), bytes: encodeJSON(manifest))
}

func validateReport(_ payload: Data, manifest: Any, counts: (files: Int, records: Int)) throws {
    let files = try validateManifest(manifest, expectedFiles: counts.files, expectedRecords: counts.records)
    guard let report = try decodeJSON(payload) as? [String: Any], let rows = report["rows"] as? [[String: Any]] else {
        throw CorpusFailure.invalid("Invalid report JSON")
    }
    try require(try integer(report["schemaVersion"], maximum: 1) == 1, "Invalid report version")
    try require(["inspect", "live"].contains(report["mode"] as? String ?? ""), "Invalid report mode")
    try require(try integer(report["totalRecords"], maximum: 100_000) == counts.records && rows.count == counts.records, "Report row count mismatch")
    _ = try integer(report["selectedRecords"], maximum: counts.records, allowsZero: true)
    let definitions = Dictionary(uniqueKeysWithValues: files.map { ($0.fileId, $0) })
    var identities = Set<String>()
    for row in rows {
        guard let fileId = row["fileId"] as? String, let file = definitions[fileId] else { throw CorpusFailure.invalid("Unknown report file identity") }
        let index = try integer(row["index"], maximum: file.expectedCount - 1, allowsZero: true)
        try require(row["fileSHA"] as? String == file.sha256, "Report source SHA-256 mismatch")
        try require(identities.insert(fileId + ":" + String(index)).inserted, "Repeated report row identity")
        try require(["notRun", "inspected", "passed", "failed", "requiresLogin", "mediaExtracted"].contains(row["status"] as? String ?? ""), "Invalid report row status")
    }
    try require(identities.count == counts.records, "Report omitted original source occurrences")
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first, ["decrypt-corpus", "encrypt-report", "decrypt-report", "seal-logs", "open-logs"].contains(command) else {
        throw CorpusFailure.invalid("Expected decrypt-corpus, encrypt-report, decrypt-report, seal-logs or open-logs")
    }
    var options: [String: String] = [:]
    let allowed = Set(["--input", "--input-sha256", "--output", "--output-dir", "--manifest", "--key-env", "--expected-files", "--expected-records"])
    try require((arguments.count - 1) % 2 == 0, "Options require a value")
    for index in stride(from: 1, to: arguments.count, by: 2) {
        let name = arguments[index]
        try require(allowed.contains(name) && options[name] == nil, "Unknown or repeated option")
        options[name] = arguments[index + 1]
    }
    guard let input = options["--input"], let fileCount = Int(options["--expected-files"] ?? "5"),
          let recordCount = Int(options["--expected-records"] ?? "1128") else { throw CorpusFailure.invalid("Missing input or invalid expected count") }
    try require((1...100).contains(fileCount) && (1...100_000).contains(recordCount), "Expected count exceeds limit")
    let counts = (files: fileCount, records: recordCount)
    let key = try loadKey(options["--key-env"] ?? "PRIVATE_SOURCE_CORPUS_KEY")
    let expectedSHA = try validSHA(options["--input-sha256"])
    let isEncryption = ["encrypt-report", "seal-logs"].contains(command)
    let original = try readBounded(URL(fileURLWithPath: input), maximum: isEncryption ? maximumPlaintext : maximumCipher)
    try require(digest(original) == expectedSHA, "Input SHA-256 mismatch")
    let output: Data
    if command == "decrypt-corpus" {
        guard let destination = options["--output-dir"] else { throw CorpusFailure.invalid("Missing --output-dir") }
        output = try unseal(original, key: key, purpose: "corpus", counts: counts)
        try extractCorpus(output, destination: URL(fileURLWithPath: destination), counts: counts)
    } else {
        guard let destination = options["--output"] else { throw CorpusFailure.invalid("Missing --output") }
        let purpose = ["seal-logs", "open-logs"].contains(command) ? "logs" : "report"
        var manifest: Any?
        if purpose == "report" {
            guard let path = options["--manifest"] else { throw CorpusFailure.invalid("Missing --manifest") }
            manifest = try decodeJSON(readBounded(URL(fileURLWithPath: path), maximum: maximumHeader))
        }
        if isEncryption {
            if let manifest { try validateReport(original, manifest: manifest, counts: counts) }
            output = try seal(original, key: key, purpose: purpose, counts: counts)
        } else {
            try requireExternalPlaintext(URL(fileURLWithPath: destination))
            output = try unseal(original, key: key, purpose: purpose, counts: counts)
            if let manifest { try validateReport(output, manifest: manifest, counts: counts) }
        }
        try writeNew(URL(fileURLWithPath: destination), bytes: output)
    }
    let summary: [String: Any] = ["command": command, "bytes": output.count, "sha256": digest(output), "files": fileCount, "records": recordCount]
    print(String(decoding: try encodeJSON(summary), as: UTF8.self))
}

do { try run() }
catch CorpusFailure.invalid(let message) {
    FileHandle.standardError.write(Data(("Private corpus operation failed: " + message + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Private corpus operation failed: file, JSON, gzip or cryptographic operation failed\n".utf8))
    exit(1)
}
