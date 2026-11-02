import Foundation
import WebKit

/// Font CSS carries a small local URL, never megabytes of base64 through the JS bridge.
enum ReaderFontResource {
    static let scheme = "readerfont"

    static func css(name: String, file: URL, isBundled: Bool = false) -> String {
        var address = URLComponents()
        address.scheme = scheme
        address.host = isBundled ? "bundle" : "custom"
        address.path = "/" + file.lastPathComponent
        guard let url = address.url else { return "" }
        let escaped = name.unicodeScalars.map { "\\" + String($0.value, radix: 16) + " " }.joined()
        let format = file.pathExtension.lowercased() == "otf" ? "opentype" : file.pathExtension.lowercased() == "woff" ? "woff" : "truetype"
        return "@font-face { font-family: \"\(escaped)\"; src: url(\"\(url.absoluteString)\") format(\"\(format)\"); font-weight: 100 900; font-style: normal; font-display: swap; }"
    }

    static func file(for url: URL, customDirectory: URL? = nil) -> URL? {
        guard url.scheme == scheme, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.pathComponents.count == 2 else { return nil }
        // Foundation's lastPathComponent can normalize an encoded slash away.
        // Validate the original encoded segment before accepting any basename.
        guard let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              encodedPath.hasPrefix("/"),
              let name = String(encodedPath.dropFirst()).removingPercentEncoding else { return nil }
        guard !name.contains("\\"), !name.contains("/"), FontImportPolicy.extensions.contains(url.pathExtension.lowercased()) else { return nil }
        if url.host == "bundle" {
            guard ["MaShanZheng-Regular.ttf", "ZhiMangXing-Regular.ttf"].contains(name) else { return nil }
            return Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "ttf")
        }
        guard url.host == "custom" else { return nil }
        let root = (customDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SourceReadSwift/Fonts", isDirectory: true))?.resolvingSymlinksInPath()
        guard let root else { return nil }
        let candidate = root.appendingPathComponent(name).resolvingSymlinksInPath()
        // URL equality also compares a directory marker; security containment
        // concerns the canonical path, not whether the caller appended a slash.
        return candidate.deletingLastPathComponent().path == root.path ? candidate : nil
    }
}

/// WebKit callbacks are main-thread-only; file reads run on a bounded serial queue.
final class ReaderFontSchemeHandler: NSObject, WKURLSchemeHandler {
    private let queue = DispatchQueue(label: "com.edc21.SourceReadSwift.font-resources", qos: .userInitiated)
    private var active: Set<ObjectIdentifier> = []

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(CocoaError(.fileReadUnknown))
            return
        }
        let key = ObjectIdentifier(urlSchemeTask as AnyObject)
        active.insert(key)
        queue.async { [weak self] in
            let outcome = Result<Data, Error> {
                guard let file = ReaderFontResource.file(for: url) else { throw CocoaError(.fileReadNoPermission) }
                let properties = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                try FontImportPolicy.validate(suffix: file.pathExtension, bytes: properties.fileSize ?? 0)
                guard properties.isRegularFile == true else { throw CocoaError(.fileReadNoPermission) }
                return try Data(contentsOf: file, options: .mappedIfSafe)
            }
            DispatchQueue.main.async {
                guard let self, self.active.remove(key) != nil else { return }
                switch outcome {
                case .success(let bytes):
                    let mime = url.pathExtension.lowercased() == "otf" ? "font/otf" : "font/ttf"
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: bytes.count, textEncodingName: nil))
                    urlSchemeTask.didReceive(bytes)
                    urlSchemeTask.didFinish()
                case .failure(let error): urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        active.remove(ObjectIdentifier(urlSchemeTask as AnyObject))
    }

    func cancelAll() { active.removeAll() }
}
