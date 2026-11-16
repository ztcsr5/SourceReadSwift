import Foundation

/// Resolves image headers with the engine's existing source session.
protocol SourceImageRequestHeadersProviding: Sendable {
    func imageRequestHeaders(source: BookSource, chapter: BookChapter) async -> Result<[String: String], SourceEngineError>
    func imageCookieHeader(for url: URL) async -> String?
}

extension SourceImageRequestHeadersProviding {
    func imageCookieHeader(for url: URL) async -> String? { nil }
}

enum SourceImageRequestHeaders {
    /// Resolves one chapter snapshot; per-image nonce/signature evaluation is not supported here.
    static func resolve(engine: SourceEngine, source: BookSource, chapter: BookChapter) async -> Result<[String: String], SourceEngineError> {
        if let provider = engine as? SourceImageRequestHeadersProviding {
            return await provider.imageRequestHeaders(source: source, chapter: chapter)
        }
        return .success(SourceRequestBuilder().imageRequestHeaders(for: source, chapterURL: chapter.url))
    }

    /// Adds only cookies matching this image URL; explicit page/source Cookie fields keep precedence.
    static func addingSessionCookies(to request: ComicImageRequest, engine: SourceEngine) async -> ComicImageRequest {
        guard let url = URL(string: request.url), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              !request.headers.keys.contains(where: { $0.caseInsensitiveCompare("Cookie") == .orderedSame }),
              let provider = engine as? SourceImageRequestHeadersProviding,
              let cookie = await provider.imageCookieHeader(for: url), !cookie.isEmpty else { return request }
        var headers = request.headers
        headers["Cookie"] = cookie
        return ComicImageRequest(url: request.url, headers: headers, decodeContext: request.decodeContext)
    }
}
