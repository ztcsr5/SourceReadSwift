import Foundation

struct ComicPage: Identifiable, Hashable, Sendable {
    let id: Int
    let url: String
    var headers: [String: String] = [:]
}

/// Distinguishes a readable prefix from a finished chapter.
struct ComicChapterResources: Sendable {
    let pages: [ComicPage]
    let hasPendingContinuation: Bool

    init(content: ChapterContent) {
        pages = ComicContentParser.parsePages(from: content)
        hasPendingContinuation = content.nextContentUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    init(offlinePages: [ComicPage]) {
        pages = offlinePages
        hasPendingContinuation = false
    }

    var canReuseFromCache: Bool { !pages.isEmpty && !hasPendingContinuation }
}

enum ComicContentParser {
    private static let wrappedImage = try! NSRegularExpression(
        pattern: #"\[img\]([\s\S]*?)\[/img\]|!\[[^\]]*\]\(([^\s\)]+)\)"#, options: .caseInsensitive)
    private static let pageContainers = ["pages", "images", "imageList", "list", "data", "result"]

    static func parsePages(from content: ChapterContent, responseURL: URL? = nil) -> [ComicPage] {
        let base = responseURL?.absoluteString ?? content.chapter.url
        var requests: [ComicImageRequest] = []
        var seen = Set<ComicImageRequest>()
        for paragraph in content.paragraphs {
            let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidates: [ComicImageRequest]
            if let first = text.first, first == "[" || first == "{", let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                candidates = parsePageEnvelope(json, base: base, remainingDepth: 6)
            } else {
                candidates = parseImageParagraph(text, base: base)
            }
            for request in candidates where isImageCandidate(request.url) && seen.insert(request).inserted {
                requests.append(request)
            }
        }
        return requests.enumerated().map { ComicPage(id: $0.offset, url: $0.element.url, headers: $0.element.headers) }
    }

    private static func parsePageEnvelope(_ value: Any, base: String, remainingDepth: Int) -> [ComicImageRequest] {
        guard remainingDepth > 0 else { return [] }
        if let address = value as? String { return ComicImageRequest.resolve(address, base: base).map { [$0] } ?? [] }
        if let pages = value as? [Any] {
            return pages.flatMap { parsePageEnvelope($0, base: base, remainingDepth: remainingDepth - 1) }
        }
        guard let object = value as? [String: Any] else { return [] }
        var foundContainer = false
        for field in pageContainers {
            guard let nested = object[field], nested is [Any] || nested is [String: Any] else { continue }
            foundContainer = true
            let pages = parsePageEnvelope(nested, base: base, remainingDepth: remainingDepth - 1)
            if !pages.isEmpty { return pages }
        }
        if foundContainer { return [] }
        return ComicImageRequest.resolve(object: object, base: base).map { [$0] } ?? []
    }

    private static func parseImageParagraph(_ text: String, base: String) -> [ComicImageRequest] {
        let imageText = ContentImageNormalizer.tokens(in: text)
        let ns = imageText as NSString
        let matches = wrappedImage.matches(in: imageText, range: NSRange(location: 0, length: ns.length))
        if !matches.isEmpty {
            return matches.compactMap { match in
                let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
                return ComicImageRequest.resolve(ns.substring(with: range), base: base)
            }
        }
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }), !text.contains("<"), !text.contains("[") else { return [] }
        let ext = URL(string: text)?.pathExtension.lowercased() ?? ""
        let isURL = text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("//")
        guard isURL || ["jpg", "jpeg", "png", "webp", "gif", "avif"].contains(ext) else { return [] }
        return ComicImageRequest.resolve(text, base: base).map { [$0] } ?? []
    }

    /// A source can be mistyped as a comic or emit its author's homepage when
    /// its own guard fails. Neither is a failed bitmap, and neither belongs in
    /// the reader's image queue. Extensionless image APIs remain supported.
    static func isImageCandidate(_ address: String) -> Bool {
        guard let url = URL(string: address) else { return false }
        if InlineImageStore.isInlineURL(url) { return true }
        let path = url.path.lowercased()
        guard !(path.isEmpty || path == "/") || url.query?.isEmpty == false else { return false }
        return !["m3u8", "mpd", "mp4", "m4v", "webm", "mp3", "m4a", "aac", "ts", "html", "htm"].contains(url.pathExtension.lowercased())
    }
}
