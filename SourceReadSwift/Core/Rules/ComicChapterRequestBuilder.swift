import Foundation

/// Prepares a chapter's shared request context for visible pages and speculative image loads.
enum ComicChapterRequestBuilder {
    static func build(resources: ComicChapterResources, source: BookSource, chapter: BookChapter,
                      engine: SourceEngine) async -> Result<[ComicImageRequest], SourceEngineError> {
        guard needsNetworkHeaders(for: resources) else {
            return .success(resources.pages.map { ComicImageRequest(url: $0.url, headers: [:]) })
        }
        let headers: [String: String]
        switch await SourceImageRequestHeaders.resolve(engine: engine, source: source, chapter: chapter) {
        case .success(let resolved): headers = resolved
        case .failure(let error): return .failure(error)
        }
        let decodeContext = SourceImageDecodeContext.resolve(source: source, chapter: chapter, engine: engine)
        var requests: [ComicImageRequest] = []
        for page in resources.pages {
            guard let address = URL(string: page.url), !address.isFileURL,
                  !InlineImageStore.isInlineURL(address) else {
                requests.append(ComicImageRequest(url: page.url, headers: [:]))
                continue
            }
            let request = ComicImageRequest(url: page.url, headers: page.headers)
            let prepared = ComicImageRequest(url: page.url,
                headers: request.mergingHeaders(headers, chapterURL: chapter.url), decodeContext: decodeContext)
            requests.append(await SourceImageRequestHeaders.addingSessionCookies(to: prepared, engine: engine))
        }
        return .success(requests)
    }

    /// Local and inline images must remain usable without running remote source scripts.
    static func needsNetworkHeaders(for resources: ComicChapterResources) -> Bool {
        resources.pages.contains { page in
            guard let scheme = URL(string: page.url)?.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
    }
}
