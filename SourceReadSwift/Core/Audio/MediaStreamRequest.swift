import AVFoundation
import Foundation

/// Preserves a source's playback request context without exposing it in player labels or errors.
struct MediaStreamRequest: Sendable {
    let url: URL
    let headers: [String: String]

    init?(_ reference: String, source: BookSource, episode: BookChapter) {
        let directive = SourceURLDirectiveParser().parse(reference)
        guard let address = MediaURLResolver.resolve(directive.urlText, base: episode.url),
              let url = URL(string: address), url.user == nil, url.password == nil else { return nil }
        self.init(url: url, headers: Self.mergingHeaders(
            SourceRequestBuilder().imageRequestHeaders(for: source, chapterURL: episode.url), explicit: directive.headers))
    }

    /// Resolves authored headers and the target URL's current cookies before creating a player item.
    static func resolve(_ reference: String, source: BookSource, episode: BookChapter,
                        engine: SourceEngine) async -> Result<MediaStreamRequest, SourceEngineError> {
        let directive = SourceURLDirectiveParser().parse(reference)
        guard let address = MediaURLResolver.resolve(directive.urlText, base: episode.url),
              let url = URL(string: address), url.user == nil, url.password == nil else {
            return .failure(.rule("媒体播放地址无效，请刷新章节或更换书源"))
        }
        let headers: [String: String]
        switch await SourceImageRequestHeaders.resolve(engine: engine, source: source, chapter: episode) {
        case .success(let resolved): headers = mergingHeaders(resolved, explicit: directive.headers)
        case .failure(let error): return .failure(error)
        }
        let request = await SourceImageRequestHeaders.addingSessionCookies(
            to: ComicImageRequest(url: url.absoluteString, headers: headers), engine: engine)
        return .success(MediaStreamRequest(url: url, headers: request.headers))
    }

    private static func mergingHeaders(_ sourceHeaders: [String: String], explicit: [String: String]) -> [String: String] {
        var headers = sourceHeaders.filter { $0.key.caseInsensitiveCompare("Accept") != .orderedSame }
        headers["Accept"] = "*/*"
        for (field, value) in explicit {
            for existing in Array(headers.keys) where existing.caseInsensitiveCompare(field) == .orderedSame {
                headers.removeValue(forKey: existing)
            }
            headers[field] = value
        }
        return headers
    }

    private init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers.filter { field, value in
            // Leave connection framing to AVFoundation; reject newlines from imported rules.
            !field.isEmpty && field.utf8.allSatisfy(Self.isFieldByte)
                && !["connection", "content-length", "host", "transfer-encoding"].contains(field.lowercased())
                && !value.contains(where: \.isNewline)
        }
    }

    func makePlayerItem() -> AVPlayerItem {
        // Keep the previously used compatibility option for Referer and other source headers.
        // AVKit owns playback; header propagation to redirected/HLS subrequests is not guaranteed.
        let options = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        return AVPlayerItem(asset: AVURLAsset(url: url, options: options))
    }

    private static func isFieldByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
            || "!#$%&'*+-.^_`|~".utf8.contains(byte)
    }
}
