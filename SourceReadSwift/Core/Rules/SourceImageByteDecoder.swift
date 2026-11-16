import CryptoKit
import Foundation

/// Lets reader and offline requests capture the engine's existing source session once per chapter.
protocol SourceImageDecodeContextProviding: Sendable {
    func makeImageDecodeContext(source: BookSource, chapter: BookChapter) -> SourceImageDecodeContext?
}

/// Carries a source's byte hook to the image download boundary, separate from chapter text parsing.
struct SourceImageDecodeContext: Hashable, Sendable {
    let source: BookSource
    let chapter: BookChapter
    let script: String
    let fingerprint: String
    let sourceValues: [String: String]
    let prepareExecution: (@Sendable (RuleExecutionContext, RulePersistentState) -> Void)?

    init?(source: BookSource, chapter: BookChapter, persistentState: RulePersistentState? = nil,
          prepareExecution: (@Sendable (RuleExecutionContext, RulePersistentState) -> Void)? = nil) {
        guard let raw = source.ruleContent?.fields["imageDecode"], Self.needsDownloadedBytes(raw) else { return nil }
        self.source = source
        self.chapter = chapter
        self.script = LegadoJavaScriptCompatibility.normalizeRuleScript(raw)
        self.prepareExecution = prepareExecution
        sourceValues = persistentState?.snapshot() ?? [:]
        let fields = [source.bookSourceUrl, source.raw["jsLib"] ?? "", script, chapter.url, chapter.bookUrl]
        var digest = SHA256()
        for value in fields + sourceValues.keys.sorted().flatMap({ [$0, sourceValues[$0] ?? ""] }) {
            digest.update(data: Data("\(value.utf8.count):".utf8))
            digest.update(data: Data(value.utf8))
        }
        fingerprint = digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func resolve(source: BookSource, chapter: BookChapter, engine: SourceEngine) -> SourceImageDecodeContext? {
        if let provider = engine as? SourceImageDecodeContextProviding {
            return provider.makeImageDecodeContext(source: source, chapter: chapter)
        }
        return SourceImageDecodeContext(source: source, chapter: chapter)
    }

    /// Preserve the app's earlier explicit URL/inline extensions; ordinary Legado hooks receive bytes.
    static func needsDownloadedBytes(_ rule: String) -> Bool {
        let raw = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let isExplicitExtension = raw.hasPrefix("@js:") || raw.hasPrefix("<js>") || raw.hasPrefix("java.")
        if !isExplicitExtension { return !raw.hasPrefix("##") }
        return raw.range(of: #"\bsrc\b|\bresult\s*(?:\[|\.\s*(?:slice|read|map|length)\b)|\b(?:BitmapFactory|ByteArrayInputStream)\b"#,
                         options: .regularExpression) != nil
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.fingerprint == rhs.fingerprint }
    func hash(into hasher: inout Hasher) { hasher.combine(fingerprint) }
}

/// Runs one downloaded image hook at a time so JavaScript byte arrays cannot multiply the image memory budget.
enum SourceImageByteDecoder {
    private static let budget = ComicImageBudget(limit: 1)

    static func decode(_ bytes: Data, sourceURL: URL, context: SourceImageDecodeContext) async -> Result<Data, ComicImageFailure> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard bytes.count <= ComicOfflineArchive.maximumPageBytes else { return .failure(.tooLarge) }
        let permit = UUID()
        guard await budget.acquire(permit) else { return .failure(.cancelled) }
        guard !Task.isCancelled else {
            await budget.release(permit)
            return .failure(.cancelled)
        }
        let decoded = await BlockingRuleExecutor.run { evaluate(bytes, sourceURL: sourceURL, context: context) }
        await budget.release(permit)
        return Task.isCancelled ? .failure(.cancelled) : decoded
    }

    private static func evaluate(_ bytes: Data, sourceURL: URL, context: SourceImageDecodeContext) -> Result<Data, ComicImageFailure> {
        let state = RulePersistentState(initialValues: context.sourceValues)
        let execution = RuleExecutionContext(persistentState: state, source: context.source, stage: "image.decode")
        context.prepareExecution?(execution, state)
        defer { execution.cleanUp() }
        let runtime = execution.jsRuntime(ajaxHandler: { _ in "" })
        // Keep binary output out of JSON numeric arrays: returning base64 bounds the bridge's extra copy.
        let quotedScript: String
        do {
            let encoded = try JSONSerialization.data(withJSONObject: context.script, options: [.fragmentsAllowed])
            quotedScript = String(decoding: encoded, as: UTF8.self)
        } catch { return .failure(.imageDecodeFailed) }
        let script = """
        (function() {
          result = java.base64DecodeToByteArray(__sourceImageBytes);
          var decoded = (0, eval)(\(quotedScript));
          if (decoded === undefined || decoded === null) decoded = result;
          if (!decoded || typeof decoded === 'string' || typeof decoded.length !== 'number')
            throw new Error('Image decode did not return bytes');
          if (decoded.length > \(ComicOfflineArchive.maximumPageBytes)) return '__image_too_large__';
          for (var i = 0; i < decoded.length; i++) {
            var byte = decoded[i];
            if (typeof byte !== 'number' || !isFinite(byte) || Math.floor(byte) !== byte || byte < -128 || byte > 255)
              throw new Error('Image decode returned an invalid byte');
            decoded[i] = byte & 255;
          }
          return java.base64Encode(Array.prototype.slice.call(decoded));
        })()
        """
        let outcome = runtime.evaluate(script, variables: [
            "__sourceImageBytes": bytes.base64EncodedString(), "src": sourceURL.absoluteString,
            "source": context.source, "chapter": context.chapter, "baseUrl": context.chapter.url
        ])
        guard case .success(let output) = outcome else { return .failure(.imageDecodeFailed) }
        guard output != "__image_too_large__", output.utf8.count <= ComicOfflineArchive.maximumPageBytes * 4 / 3 + 8 else {
            return .failure(.tooLarge)
        }
        guard let decoded = Data(base64Encoded: output), !decoded.isEmpty,
              InlineImageDecoder.imageFileExtension(for: decoded) != nil else { return .failure(.invalidImage) }
        return .success(decoded)
    }
}
