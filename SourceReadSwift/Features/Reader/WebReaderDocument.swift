import CoreGraphics
import CoreText
import Foundation
import SwiftUI
import UIKit

enum ReaderTextTransform {
    static func toTraditionalChinese(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Hans-Hant" as CFString, false)
        return mutable as String
    }

    static func displayText(_ text: String, traditionalChineseEnabled: Bool) -> String {
        guard traditionalChineseEnabled else { return text }
        return toTraditionalChinese(text)
    }

    static func displayText(_ text: String, traditionalChinese: Bool) -> String {
        displayText(text, traditionalChineseEnabled: traditionalChinese)
    }

    static func bionicAttributedString(for text: String, regularFont: Font? = nil, boldFont: Font? = nil) -> AttributedString {
        guard !text.isEmpty else { return AttributedString() }
        var result = AttributedString()
        var index = text.startIndex
        var cjkRunCount = 0

        while index < text.endIndex {
            let ch = text[index]
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                cjkRunCount = 0
                var wordEnd = text.index(after: index)
                while wordEnd < text.endIndex, text[wordEnd].isASCII && (text[wordEnd].isLetter || text[wordEnd].isNumber) {
                    wordEnd = text.index(after: wordEnd)
                }
                let word = String(text[index..<wordEnd])
                let count = word.count
                let boldCount = max(1, Int(ceil(Double(count) * 0.45)))
                let splitIdx = word.index(word.startIndex, offsetBy: min(boldCount, count))
                var head = AttributedString(String(word[..<splitIdx]))
                if let boldFont {
                    head.font = boldFont
                } else {
                    head.inlinePresentationIntent = .stronglyEmphasized
                }
                result.append(head)
                if splitIdx < word.endIndex {
                    var tail = AttributedString(String(word[splitIdx...]))
                    if let regularFont {
                        tail.font = regularFont
                    }
                    result.append(tail)
                }
                index = wordEnd
                continue
            }

            let nextIndex = text.index(after: index)
            var part = AttributedString(String(ch))
            if isCJKIdeograph(ch) {
                let isBold = (cjkRunCount % 4) < 2
                if isBold {
                    if let boldFont {
                        part.font = boldFont
                    } else {
                        part.inlinePresentationIntent = .stronglyEmphasized
                    }
                } else if let regularFont {
                    part.font = regularFont
                }
                cjkRunCount += 1
            } else {
                cjkRunCount = 0
                if let regularFont {
                    part.font = regularFont
                }
            }
            result.append(part)
            index = nextIndex
        }
        return result
    }

    static func bionicAttributedString(_ text: String, regularFont: Font, boldFont: Font) -> AttributedString {
        bionicAttributedString(for: text, regularFont: regularFont, boldFont: boldFont)
    }

    static func bionicAttributedString(
        _ text: String,
        baseFont: UIFont,
        textColor: UIColor,
        lineSpacing: CGFloat,
        letterSpacing: CGFloat
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .kern: letterSpacing
        ]
        let boldFont: UIFont = {
            if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: descriptor, size: baseFont.pointSize)
            }
            return UIFont.boldSystemFont(ofSize: baseFont.pointSize)
        }()
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        var index = text.startIndex
        var cjkRunCount = 0
        while index < text.endIndex {
            let ch = text[index]
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                cjkRunCount = 0
                var wordEnd = text.index(after: index)
                while wordEnd < text.endIndex, text[wordEnd].isASCII && (text[wordEnd].isLetter || text[wordEnd].isNumber) {
                    wordEnd = text.index(after: wordEnd)
                }
                let word = String(text[index..<wordEnd])
                let boldCount = max(1, Int(ceil(Double(word.count) * 0.45)))
                let splitIdx = text.index(index, offsetBy: min(boldCount, word.count))
                let nsRange = NSRange(index..<splitIdx, in: text)
                result.addAttribute(.font, value: boldFont, range: nsRange)
                index = wordEnd
                continue
            }
            let nextIndex = text.index(after: index)
            if isCJKIdeograph(ch) {
                if (cjkRunCount % 4) < 2 {
                    let nsRange = NSRange(index..<nextIndex, in: text)
                    result.addAttribute(.font, value: boldFont, range: nsRange)
                }
                cjkRunCount += 1
            } else {
                cjkRunCount = 0
            }
            index = nextIndex
        }
        return result
    }

    private static func isCJKIdeograph(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0xF900...0xFAFF).contains(v)
    }
}

enum WebReaderCustomFontCache {
    private static let lock = NSLock()
    private static var cachedPostScriptName: String = ""
    private static var cachedCSS: String = ""

    static func fontFaceCSSForActiveCustomFont() -> String {
        let postScript = (UserDefaults.standard.string(forKey: "reader.customFontPostScriptName") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !postScript.isEmpty else { return "" }

        lock.lock()
        if cachedPostScriptName == postScript, !cachedCSS.isEmpty {
            let hit = cachedCSS
            lock.unlock()
            return hit
        }
        lock.unlock()

        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return ""
        }
        let fontsDir = appSupport
            .appendingPathComponent("SourceReadSwift", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil) else {
            return ""
        }

        for fileURL in files {
            guard let provider = CGDataProvider(url: fileURL as CFURL),
                  let cgFont = CGFont(provider) else { continue }
            let psName = (cgFont.postScriptName as String?) ?? fileURL.deletingPathExtension().lastPathComponent
            guard psName == postScript else { continue }
            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { continue }
            let ext = fileURL.pathExtension.lowercased()
            let (mime, format): (String, String) = {
                switch ext {
                case "otf": return ("font/otf", "opentype")
                case "woff": return ("font/woff", "woff")
                case "ttc": return ("font/collection", "truetype")
                default: return ("font/ttf", "truetype")
                }
            }()
            let base64 = data.base64EncodedString()
            let escapedName = postScript.replacingOccurrences(of: "\"", with: "\\\"")
            let css = "@font-face { font-family: \"\(escapedName)\"; src: url(\"data:\(mime);base64,\(base64)\") format(\"\(format)\"); font-weight: 100 900; font-style: normal; font-display: swap; }"
            lock.lock()
            cachedPostScriptName = postScript
            cachedCSS = css
            lock.unlock()
            return css
        }
        return ""
    }
}

/// One chapter as the WebView scroll surface consumes it.
///
/// The TextKit surface took a flat `[String]` and therefore could not tell a
/// chapter divider from body text — that is why the divider title inherited the
/// body font. The WebView surface needs the chapter structure to give every
/// title its own element and CSS rule, so the sections travel explicitly and
/// the flat index space is derived from them with the same rule the paged model
/// and `ReaderChapterWindowPolicy` already use.
struct WebReaderSection: Equatable {
    let chapterIndex: Int
    let title: String
    let paragraphs: [String]
    var isReady: Bool = true

    /// Stable identity inside the WebView document. Chapter indices are unique
    /// inside one reading window, and a chapter that is re-fetched keeps its
    /// element so an in-place refresh does not move the reading position.
    var key: String { "c\(chapterIndex)" }

    /// Cheap structural signature: the DOM is only rebuilt for sections whose
    /// content really changed.
    var contentSignature: String {
        let head = paragraphs.first?.hashValue ?? 0
        let tail = paragraphs.last?.hashValue ?? 0
        return "\(chapterIndex)|\(title.hashValue)|\(paragraphs.count)|\(head)|\(tail)|\(isReady ? "r" : "l")"
    }
}

/// Flat paragraph space shared with `ReaderChapterWindowPolicy.layout`.
///
/// The first section starts at 0; every later section spends exactly one flat
/// index on its divider title. Keeping this rule in one place is what lets a
/// scroll report, a paged page and a persisted reading position agree.
enum WebReaderFlatIndexPolicy {
    static func starts(forParagraphCounts counts: [Int]) -> [Int] {
        var result: [Int] = []
        var cursor = 0
        for (offset, count) in counts.enumerated() {
            // 从第二章起先占掉一个扁平位给分隔用的章标题。
            if offset > 0 { cursor += 1 }
            result.append(cursor)
            cursor += max(count, 0)
        }
        return result
    }

    static func totalCount(forParagraphCounts counts: [Int]) -> Int {
        guard !counts.isEmpty else { return 0 }
        return counts.reduce(0, +) + (counts.count - 1)
    }
}

/// Everything the document needs in order to render one frame of typography.
struct WebReaderStylePayload: Equatable {
    var fontFamilyCSS: String
    var fontFamilyWeight: Int
    var fontSize: Double
    var lineHeight: Double
    var letterSpacing: Double
    var paragraphSpacing: Double
    var paragraphIndent: Double
    var sidePadding: Double
    var topInset: Double
    var bottomInset: Double
    var titleSize: Double
    var titleSpacing: Double
    var textColor: String
    var surfaceColor: String
    var highlightColor: String
    var accentColor: String
    var selectable: Bool
    var customFontFaceCSS: String = ""
    var traditionalChineseEnabled: Bool = false
    var bionicReadingEnabled: Bool = false

    /// `lineSpacing` in the TextKit surface is *extra* leading between lines, so
    /// the CSS line box has to grow by that amount instead of replacing it.
    static func lineHeight(fontSize: Double, extraLineSpacing: Double) -> Double {
        guard fontSize > 0 else { return 1.6 }
        return max((fontSize + max(extraLineSpacing, 0)) / fontSize, 1.0)
    }

    /// A chapter title has to be recognisable at a glance. The TextKit surface
    /// used `fontSize + 8` in the body colour, which read as another paragraph.
    static func titleSize(fontSize: Double) -> Double {
        max(fontSize * 1.3, fontSize + 6)
    }

    var jsonObject: [String: Any] {
        [
            "fontFamily": fontFamilyCSS,
            "fontWeight": fontFamilyWeight,
            "fontSize": fontSize,
            "lineHeight": lineHeight,
            "letterSpacing": letterSpacing,
            "paragraphSpacing": paragraphSpacing,
            "paragraphIndent": paragraphIndent,
            "sidePadding": sidePadding,
            "topInset": topInset,
            "bottomInset": bottomInset,
            "titleSize": titleSize,
            "titleSpacing": titleSpacing,
            "textColor": textColor,
            "surfaceColor": surfaceColor,
            "highlightColor": highlightColor,
            "accentColor": accentColor,
            "selectable": selectable,
            "customFontFaceCSS": customFontFaceCSS,
            "traditionalChinese": traditionalChineseEnabled,
            "bionicReading": bionicReadingEnabled
        ]
    }

    static func make(
        fontFamily: ReaderFontFamily,
        fontSize: Double,
        lineSpacing: Double,
        pagePadding: Double,
        letterSpacing: Double,
        paragraphSpacing: Double,
        paragraphIndent: Double,
        titleSpacing: Double,
        footerHeight: Double,
        topInset: Double?,
        textColor: UIColor,
        surfaceColor: UIColor,
        highlightColor: UIColor,
        accentColor: UIColor,
        selectable: Bool,
        traditionalChineseEnabled: Bool = false,
        bionicReadingEnabled: Bool = false
    ) -> WebReaderStylePayload {
        let resolvedTop = topInset ?? max(pagePadding + 10, 24)
        let isTransparentSurface = surfaceColor.cgColor.alpha <= 0.001
        let resolvedSurface = isTransparentSurface ? "transparent" : WebReaderColor.hex(surfaceColor)
        let fontFaceCSS = fontFamily == .custom ? WebReaderCustomFontCache.fontFaceCSSForActiveCustomFont() : ""
        return WebReaderStylePayload(
            fontFamilyCSS: fontFamily.webCSSFamily,
            fontFamilyWeight: fontFamily.webCSSWeight,
            fontSize: fontSize,
            lineHeight: lineHeight(fontSize: fontSize, extraLineSpacing: lineSpacing),
            letterSpacing: letterSpacing,
            paragraphSpacing: paragraphSpacing,
            paragraphIndent: paragraphIndent,
            sidePadding: pagePadding,
            topInset: max(resolvedTop, 0),
            bottomInset: max(footerHeight + pagePadding * 0.6, 24),
            titleSize: titleSize(fontSize: fontSize),
            titleSpacing: max(titleSpacing, 0),
            textColor: WebReaderColor.hex(textColor),
            surfaceColor: resolvedSurface,
            highlightColor: WebReaderColor.hex(highlightColor),
            accentColor: WebReaderColor.hex(accentColor),
            selectable: selectable,
            customFontFaceCSS: fontFaceCSS,
            traditionalChineseEnabled: traditionalChineseEnabled,
            bionicReadingEnabled: bionicReadingEnabled
        )
    }
}

/// Builds the JSON body posted into `window.__reader.setContent`.
enum WebReaderContentPayloadBuilder {
    static func payload(
        sections: [WebReaderSection],
        showChapterEndBadge: Bool,
        traditionalChineseEnabled: Bool = false
    ) -> [String: Any] {
        let starts = WebReaderFlatIndexPolicy.starts(forParagraphCounts: sections.map { $0.paragraphs.count })
        var encoded: [[String: Any]] = []
        encoded.reserveCapacity(sections.count)

        for (offset, section) in sections.enumerated() {
            let start = offset < starts.count ? starts[offset] : 0
            let isFirst = offset == 0
            let titleFlat = isFirst ? start : max(start - 1, 0)
            var paragraphs: [[String: Any]] = []
            paragraphs.reserveCapacity(section.paragraphs.count)

            for (index, paragraph) in section.paragraphs.enumerated() {
                let flat = start + index
                let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                if let imageURL = ReaderImageSizingPolicy.imageURL(in: paragraph) {
                    paragraphs.append([
                        "flat": flat,
                        "local": index,
                        "image": WebReaderImageScheme.source(for: imageURL)
                    ])
                    continue
                }
                // Divider paragraphs written by older window builds carry the
                // "——— title ———" decoration. The WebView draws a real title
                // element instead, so the decoration must not be printed twice.
                let stripped = Self.strippingLegacyDividerDecoration(trimmed)
                let text = ReaderTextTransform.displayText(stripped, traditionalChineseEnabled: traditionalChineseEnabled)
                paragraphs.append(["flat": flat, "local": index, "text": text])
            }

            let displayTitle = ReaderTextTransform.displayText(section.title, traditionalChineseEnabled: traditionalChineseEnabled)
            let sigSuffix = traditionalChineseEnabled ? "|tc1" : ""
            var entry: [String: Any] = [
                "key": section.key,
                "chapter": section.chapterIndex,
                "title": displayTitle,
                "start": start,
                "titleFlat": titleFlat,
                "first": isFirst,
                "sig": section.contentSignature + sigSuffix,
                "paragraphs": paragraphs
            ]
            if !section.isReady, section.paragraphs.isEmpty {
                entry["loading"] = true
            }
            if showChapterEndBadge {
                entry["end"] = true
            }
            encoded.append(entry)
        }

        return [
            "sections": encoded,
            "total": WebReaderFlatIndexPolicy.totalCount(forParagraphCounts: sections.map { $0.paragraphs.count })
        ]
    }

    private static func strippingLegacyDividerDecoration(_ text: String) -> String {
        guard text.hasPrefix("——— "), text.hasSuffix(" ———") else { return text }
        let inner = text.dropFirst(4).dropLast(4).trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? text : inner
    }
}

/// Converts UIKit colours into the CSS over `wkWebView` renders.
enum WebReaderColor {
    static func hex(_ color: UIColor, traits: UITraitCollection = .current) -> String {
        let resolved = color.resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return String(
                format: "#%02X%02X%02X%02X",
                Int((red * 255).rounded()),
                Int((green * 255).rounded()),
                Int((blue * 255).rounded()),
                Int((alpha * 255).rounded())
            )
        }
        let components = resolved.cgColor.components ?? [0, 0, 0, 1]
        if components.count >= 3 {
            return String(
                format: "#%02X%02X%02X%02X",
                Int((components[0] * 255).rounded()),
                Int((components[1] * 255).rounded()),
                Int((components[2] * 255).rounded()),
                components.count > 3 ? Int((components[3] * 255).rounded()) : 255
            )
        }
        return components.first.map { _ in "#FF000000" } ?? "#FF000000"
    }
}

/// Custom scheme used for chapter illustrations.
///
/// A plain `file://` or `https://` image cannot carry the source's `Referer`
/// and `User-Agent`, and most Chinese illustration CDNs answer 403 without
/// them. Every `[img]url[/img]` paragraph therefore renders as
/// `readerimg://i/<base64url>` and the scheme handler performs the request with
/// the same headers the TextKit surface used.
enum WebReaderImageScheme {
    static let name = "readerimg"

    static func source(for url: URL) -> String {
        "\(name)://i/\(base64URL(url.absoluteString))"
    }

    static func originalURL(from source: String) -> URL? {
        guard let separator = source.range(of: "://") else { return nil }
        var rest = String(source[separator.upperBound...])
        if rest.hasPrefix("i/") { rest.removeFirst(2) }
        guard let decoded = base64URLDecode(rest) else { return nil }
        return URL(string: decoded)
    }

    static func base64URL(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ text: String) -> String? {
        var normalized = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: normalized) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Escapes an arbitrary UTF-8 string so it can be embedded inside a JavaScript
/// string literal passed to `evaluateJavaScript`.
enum WebReaderJavaScriptLiteral {
    static func string(_ value: String) -> String {
        var output = "\""
        output.reserveCapacity(value.count + 16)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{2028}": output += "\\u2028"
            case "\u{2029}": output += "\\u2029"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        output += "\""
        return output
    }
}

extension ReaderFontFamily {
    /// CSS family stack. The WebView resolves the first installed member, which
    /// keeps the reader's font picker working without shipping font files.
    var webCSSFamily: String {
        switch self {
        case .system:
            return "-apple-system, \"PingFang SC\", \"Helvetica Neue\", sans-serif"
        case .light:
            return "-apple-system, \"PingFang SC\", \"Helvetica Neue\", sans-serif"
        case .bold:
            return "-apple-system, \"PingFang SC\", \"Helvetica Neue\", sans-serif"
        case .songti:
            return "\"Songti SC\", \"STSong\", \"SimSun\", serif"
        case .kaiti:
            return "\"Kaiti SC\", \"STKaiti\", \"KaiTi\", serif"
        case .rounded:
            return "ui-rounded, \"SF Pro Rounded\", -apple-system, sans-serif"
        case .custom:
            let postScript = UserDefaults.standard.string(forKey: "reader.customFontPostScriptName") ?? ""
            let trimmed = postScript.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "-apple-system, \"PingFang SC\", sans-serif"
                : "\"\(trimmed)\", -apple-system, sans-serif"
        }
    }

    /// `font-weight` that reproduces the TextKit weight choice for each family.
    var webCSSWeight: Int {
        switch self {
        case .light: return 300
        case .bold: return 600
        case .songti, .kaiti: return 400
        case .rounded: return 500
        case .system, .custom: return 400
        }
    }
}

/// Self-contained document rendered by the scroll surface.
///
/// Nothing is fetched from disk or network: the shell only declares CSS
/// variables and the small JavaScript bridge that applies content, reports
/// position and turns a short tap into a zone event. All content arrives later
/// through `window.__reader.setContent`, which patches the DOM in place instead
/// of reloading the document — reloading is what used to blank the screen on a
/// chapter jump.
enum WebReaderHTML {
    static let shell: String = #"""
    <!doctype html>
    <html lang="zh-Hans">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no, viewport-fit=cover">
    <meta name="format-detection" content="telephone=no,email=no,address=no">
    <style>
    :root {
      --font-family: -apple-system, "PingFang SC", sans-serif;
      --font-weight: 400;
      --font-size: 18px;
      --line-height: 1.6;
      --letter-spacing: 0px;
      --para-gap: 12px;
      --indent: 0px;
      --side: 22px;
      --top: 56px;
      --bottom: 32px;
      --title-size: 26px;
      --title-gap: 18px;
      --text: #1C1C1E;
      --bg: #F7F4EE;
      --hl: rgba(90, 80, 220, 0.12);
      --accent: #5A50DC;
      --select: none;
    }
    html { -webkit-text-size-adjust: 100%; }
    body {
      margin: 0;
      padding: var(--top) var(--side) var(--bottom);
      background: var(--bg);
      color: var(--text);
      font-family: var(--font-family);
      font-weight: var(--font-weight);
      font-size: var(--font-size);
      line-height: var(--line-height);
      letter-spacing: var(--letter-spacing);
      -webkit-user-select: var(--select);
      user-select: var(--select);
      -webkit-touch-callout: var(--select);
      overflow-wrap: break-word;
      word-break: break-word;
      -webkit-font-smoothing: antialiased;
      -webkit-tap-highlight-color: transparent;
    }
    #content { display: block; }
    .chapter { display: block; contain: layout style paint; }
    .chapter-title {
      margin: calc(var(--title-gap) * 1.9) calc(var(--side) * -0.32) var(--title-gap);
      text-align: left;
      text-indent: 0;
      padding-left: 0.62em;
      border-left: 3px solid var(--accent);
      font-size: var(--title-size);
      line-height: 1.36;
      font-weight: 700;
      letter-spacing: 0.01em;
      color: var(--text);
    }
    .chapter.first .chapter-title { margin-top: calc(var(--title-gap) * 0.5); }
    .para {
      margin: 0 0 var(--para-gap) 0;
      text-indent: var(--indent);
      white-space: pre-wrap;
      /* Chinese prose reads as a block when every line shares the same
         left *and* right edge. WebKit needs the ideograph keyword; without
         it Safari falls back to ragged-right and the page looks untidy. */
      text-align: justify;
      text-align-last: left;
      text-justify: inter-ideograph;
    }
    .para b.br {
      font-weight: 700;
    }
    .para.hl {
      background: var(--hl);
      border-radius: 6px;
      box-shadow: 0 0 0 3px var(--hl);
    }
    .para.image {
      margin: calc(var(--para-gap) * 1.2) 0;
      text-align: center;
      text-indent: 0;
    }
    .para.image img {
      max-width: 100%;
      height: auto;
      border-radius: 8px;
      background: rgba(127, 127, 127, 0.10);
      vertical-align: top;
    }
    .chapter-loading, .chapter-end {
      margin: calc(var(--para-gap) * 2) 0;
      text-align: center;
      font-size: 0.8em;
      opacity: 0.44;
    }
    </style>
    </head>
    <body>
    <main id="content"></main>
    <script>
    (function () {
      "use strict";
      var content = document.getElementById("content");
      var root = document.documentElement;
      var state = {
        style: null,
        sections: Object.create(null),
        order: [],
        nodes: [],
        visible: -1,
        highlightEl: null,
        lastScrollAt: 0,
        ticking: false,
        nearTop: false,
        nearBottom: false,
        reachBottom: false,
        selection: false,
        customFontCSS: "",
        bionicReading: false
      };

      function post(message) {
        try {
          var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reader;
          if (bridge) { bridge.postMessage(message); }
        } catch (error) {}
      }

      function px(value) { return (Math.round(value * 100) / 100) + "px"; }

      function topInset() { return state.style ? state.style.topInset : 0; }

      // 页面脚本一旦抛错，WebKit 会停在半渲染状态（白屏且不响应滚动）。
      // 把第一个错误回传给原生侧，由它重建一次文档，用户不用退 App。
      window.addEventListener("error", function (event) {
        post({ type: "fatal", message: String((event && event.message) || "script-error") });
      });

      function applyCustomFontCSS(css) {
        var nextCSS = css || "";
        if (state.customFontCSS === nextCSS) { return; }
        state.customFontCSS = nextCSS;
        var existing = document.getElementById("reader-custom-font");
        if (!nextCSS) {
          if (existing && existing.parentNode) { existing.parentNode.removeChild(existing); }
          return;
        }
        if (!existing) {
          existing = document.createElement("style");
          existing.id = "reader-custom-font";
          if (document.head) { document.head.appendChild(existing); }
        }
        existing.textContent = nextCSS;
      }

      function renderParagraphText(element, rawText, bionic) {
        element.setAttribute("data-raw-text", rawText);
        if (!bionic || !rawText) {
          element.textContent = rawText;
          return;
        }
        var fragment = document.createDocumentFragment();
        var tokenRegex = /([A-Za-z0-9\u00C0-\u024F]{2,}|[\u4E00-\u9FFF]{2,})/g;
        var lastIndex = 0;
        var match;
        while ((match = tokenRegex.exec(rawText)) !== null) {
          if (match.index > lastIndex) {
            fragment.appendChild(document.createTextNode(rawText.slice(lastIndex, match.index)));
          }
          var token = match[0];
          var firstCode = token.charCodeAt(0);
          var isCJK = firstCode >= 0x4E00 && firstCode <= 0x9FFF;
          if (isCJK) {
            var pos = 0;
            while (pos < token.length) {
              var chunk = token.slice(pos, pos + 4);
              var boldLen = Math.min(2, Math.max(1, Math.floor(chunk.length / 2)));
              var bNode = document.createElement("b");
              bNode.className = "br";
              bNode.textContent = chunk.slice(0, boldLen);
              fragment.appendChild(bNode);
              if (chunk.length > boldLen) {
                fragment.appendChild(document.createTextNode(chunk.slice(boldLen)));
              }
              pos += 4;
            }
          } else {
            var lead = Math.max(1, Math.ceil(token.length * 0.45));
            var bWord = document.createElement("b");
            bWord.className = "br";
            bWord.textContent = token.slice(0, lead);
            fragment.appendChild(bWord);
            if (token.length > lead) {
              fragment.appendChild(document.createTextNode(token.slice(lead)));
            }
          }
          lastIndex = tokenRegex.lastIndex;
        }
        if (lastIndex < rawText.length) {
          fragment.appendChild(document.createTextNode(rawText.slice(lastIndex)));
        }
        element.replaceChildren(fragment);
      }

      function setStyle(style) {
        var anchor = captureAnchor();
        var prevBionic = state.bionicReading;
        state.style = style;
        state.bionicReading = !!style.bionicReading;
        applyCustomFontCSS(style.customFontFaceCSS || "");
        root.style.setProperty("--font-family", style.fontFamily);
        root.style.setProperty("--font-weight", String(style.fontWeight));
        root.style.setProperty("--font-size", px(style.fontSize));
        root.style.setProperty("--line-height", String(style.lineHeight));
        root.style.setProperty("--letter-spacing", px(style.letterSpacing));
        root.style.setProperty("--para-gap", px(style.paragraphSpacing));
        root.style.setProperty("--indent", px(style.paragraphIndent));
        root.style.setProperty("--side", px(style.sidePadding));
        root.style.setProperty("--top", px(style.topInset));
        root.style.setProperty("--bottom", px(style.bottomInset));
        root.style.setProperty("--title-size", px(style.titleSize));
        root.style.setProperty("--title-gap", px(style.titleSpacing));
        root.style.setProperty("--text", style.textColor);
        root.style.setProperty("--bg", style.surfaceColor);
        root.style.setProperty("--hl", style.highlightColor);
        root.style.setProperty("--accent", style.accentColor);
        root.style.setProperty("--select", style.selectable ? "text" : "none");
        if (prevBionic !== state.bionicReading) {
          var paras = content.querySelectorAll(".para:not(.image)");
          for (var i = 0; i < paras.length; i += 1) {
            var raw = paras[i].getAttribute("data-raw-text") || paras[i].textContent || "";
            renderParagraphText(paras[i], raw, state.bionicReading);
          }
        }
        refreshMetrics();
        restoreAnchor(anchor);
      }

      function buildSection(section) {
        var node = document.createElement("section");
        node.className = section.first ? "chapter first" : "chapter";
        node.setAttribute("data-key", section.key);
        node.setAttribute("data-chapter", String(section.chapter));
        node.setAttribute("data-sig", section.sig);
        node.setAttribute("data-start", String(section.start));

        var heading = document.createElement(section.first ? "h1" : "h2");
        heading.className = "chapter-title";
        heading.setAttribute("data-flat", String(section.titleFlat));
        heading.setAttribute("data-local", "-1");
        heading.textContent = section.title;
        node.appendChild(heading);

        var fragment = document.createDocumentFragment();
        for (var index = 0; index < section.paragraphs.length; index += 1) {
          var paragraph = section.paragraphs[index];
          if (paragraph.image) {
            var figure = document.createElement("figure");
            figure.className = "para image";
            figure.setAttribute("data-flat", String(paragraph.flat));
            figure.setAttribute("data-local", String(paragraph.local));
            var image = document.createElement("img");
            image.setAttribute("src", paragraph.image);
            image.setAttribute("decoding", "async");
            figure.appendChild(image);
            fragment.appendChild(figure);
            continue;
          }
          var element = document.createElement("p");
          element.className = "para";
          element.setAttribute("data-flat", String(paragraph.flat));
          element.setAttribute("data-local", String(paragraph.local));
          renderParagraphText(element, paragraph.text, state.bionicReading);
          fragment.appendChild(element);
        }
        node.appendChild(fragment);

        if (section.loading) {
          var loading = document.createElement("p");
          loading.className = "chapter-loading";
          loading.textContent = "正在加载章节内容…";
          node.appendChild(loading);
        } else if (section.end) {
          var end = document.createElement("p");
          end.className = "chapter-end";
          end.textContent = "— — — 本章完 — — —";
          node.appendChild(end);
        }
        return node;
      }

      // 章节窗口在上方插入一章后，后面每一章的整体扁平索引都会平移。
      // 段落节点被复用（内容没变），但它们的 data-flat 必须跟着章节起点重算，
      // 否则可见段落回报与跳转会落在旧编号上——正是「跳章后位置乱掉」的成因。
      function rebaseSection(node, section) {
        if (node.getAttribute("data-start") === String(section.start)) { return; }
        node.setAttribute("data-start", String(section.start));
        var children = node.querySelectorAll("[data-flat]");
        for (var index = 0; index < children.length; index += 1) {
          var local = parseInt(children[index].getAttribute("data-local"), 10);
          if (isNaN(local)) { continue; }
          var flat = local < 0 ? section.titleFlat : section.start + local;
          children[index].setAttribute("data-flat", String(flat));
        }
      }

      function isPrefixPreserved(payload) {
        var previous = state.order;
        if (!previous.length) { return false; }
        for (var index = 0; index < previous.length; index += 1) {
          if (!payload.sections[index] || payload.sections[index].key !== previous[index]) { return false; }
          var node = state.sections[previous[index]];
          if (!node || node.getAttribute("data-sig") !== payload.sections[index].sig) { return false; }
        }
        return true;
      }

      function setContent(payload) {
        var anchor = captureAnchor();
        var nextSections = Object.create(null);
        var nextOrder = [];
        var prefixRebuilt = false;
        var previousLength = state.order.length;

        for (var index = 0; index < payload.sections.length; index += 1) {
          var section = payload.sections[index];
          var existing = state.sections[section.key];
          if (existing && existing.getAttribute("data-sig") === section.sig) {
            rebaseSection(existing, section);
            nextSections[section.key] = existing;
          } else {
            nextSections[section.key] = buildSection(section);
            if (index < previousLength) {
              prefixRebuilt = true;
            }
          }
          nextOrder.push(section.key);
        }

        var sameShape = isPrefixPreserved(payload)
          && nextOrder.length >= previousLength
          && !prefixRebuilt;

        if (sameShape) {
          for (var tail = previousLength; tail < nextOrder.length; tail += 1) {
            content.appendChild(nextSections[nextOrder[tail]]);
          }
        } else {
          var fragment = document.createDocumentFragment();
          for (var nodeIndex = 0; nodeIndex < nextOrder.length; nodeIndex += 1) {
            fragment.appendChild(nextSections[nextOrder[nodeIndex]]);
          }
          content.replaceChildren(fragment);
        }

        state.sections = nextSections;
        state.order = nextOrder;
        state.visible = -1;
        refreshMetrics();
        if (!sameShape) {
          restoreAnchor(anchor);
        }
        post({ type: "content-ready", total: payload.total });
        window.requestAnimationFrame(onScroll);
      }

      function refreshMetrics() {
        state.nodes = Array.prototype.slice.call(content.querySelectorAll("[data-flat]"));
      }

      function nodeMetric(element) {
        var rect = element.getBoundingClientRect();
        var section = element.closest ? element.closest("[data-key]") : null;
        return {
          flat: parseInt(element.getAttribute("data-flat"), 10) || 0,
          local: parseInt(element.getAttribute("data-local"), 10) || 0,
          key: section ? section.getAttribute("data-key") : "",
          top: rect.top + window.scrollY,
          height: Math.max(rect.height, 1)
        };
      }

      function metricAt(y) {
        var list = state.nodes;
        if (!list.length) { return null; }
        var low = 0;
        var high = list.length - 1;
        var found = -1;
        while (low <= high) {
          var middle = (low + high) >> 1;
          var top = list[middle].getBoundingClientRect().top + window.scrollY;
          if (top <= y) { found = middle; low = middle + 1; }
          else { high = middle - 1; }
        }
        var picked = found < 0 ? list[0] : list[found];
        return nodeMetric(picked);
      }

      function captureAnchor() {
        if (!state.nodes.length) { return null; }
        var metric = metricAt(window.scrollY + topInset() + 1);
        if (!metric) { return null; }
        var offset = window.scrollY + topInset() + 1 - metric.top;
        return {
          key: metric.key,
          local: metric.local,
          fraction: Math.min(Math.max(offset / metric.height, 0), 1)
        };
      }

      function safeScrollTo(y) {
        if (!isFinite(y)) { return false; }
        window.scrollTo(0, Math.max(y, 0));
        return true;
      }

      function restoreAnchor(anchor) {
        if (!anchor || !anchor.key) { return; }
        var selector = '[data-key="' + anchor.key + '"] [data-local="' + anchor.local + '"]';
        var element = content.querySelector(selector);
        if (!element) { return; }
        var rect = element.getBoundingClientRect();
        var top = rect.top + window.scrollY;
        var height = Math.max(rect.height, 1);
        var target = Math.max(top - topInset() + height * anchor.fraction, 0);
        if (!isFinite(target) || Math.abs(target - window.scrollY) < 1) { return; }
        safeScrollTo(target);
      }

      function elementForFlat(flat) {
        var exact = content.querySelector('[data-flat="' + flat + '"]');
        if (exact) { return exact; }
        var list = state.nodes;
        var best = null;
        var bestFlat = -1;
        for (var index = 0; index < list.length; index += 1) {
          var nodeFlat = parseInt(list[index].getAttribute("data-flat"), 10);
          if (isNaN(nodeFlat)) { continue; }
          if (nodeFlat <= flat && nodeFlat > bestFlat) {
            bestFlat = nodeFlat;
            best = list[index];
          }
          if (nodeFlat > flat) { break; }
        }
        return best;
      }

      function onScroll() {
        state.ticking = false;
        state.lastScrollAt = performance.now();
        var y = window.scrollY;
        var viewport = window.innerHeight;
        var height = document.documentElement.scrollHeight;
        var metric = metricAt(y + topInset() + 4);
        if (metric && metric.flat !== state.visible) {
          state.visible = metric.flat;
          // 快速滚动时段落每几毫秒就换一次，逐条回传会让 SwiftUI 整棵阅读器
          // 树每帧重算。120ms 一条足够记进度，也不会把主线程塞满。
          var now = performance.now();
          if (now - (state.lastVisiblePostAt || 0) > 120) {
            state.lastVisiblePostAt = now;
            post({ type: "visible", flat: metric.flat });
          }
        }
        var bottom = y + viewport;
        // 预取要早于「看不见下一章」的那一刻：离末尾还剩约 3.5 屏就开始要下一章，
        // 这样追加发生在用户滑到尽头之前，滚动不会被文档底部卡住。
        var nearMargin = Math.max(2800, viewport * 3.5);
        var resetMargin = nearMargin + 900;
        if (height > 0 && bottom >= height - nearMargin) {
          if (!state.nearBottom) { state.nearBottom = true; post({ type: "near-bottom" }); }
        } else if (bottom < height - resetMargin) {
          state.nearBottom = false;
        }
        if (y <= nearMargin) {
          if (!state.nearTop) { state.nearTop = true; post({ type: "near-top" }); }
        } else if (y > resetMargin) {
          state.nearTop = false;
        }
        if (height > 0 && bottom >= height + 40) {
          if (!state.reachBottom) { state.reachBottom = true; post({ type: "reach-bottom" }); }
        } else if (bottom < height) {
          state.reachBottom = false;
        }
        if (y <= -40) { post({ type: "reach-top" }); }
      }

      window.addEventListener("scroll", function () {
        // 时间戳必须在事件当帧同步记下：`onScroll` 是 rAF 延迟执行的，
        // 若等它再记，紧接着的一次轻点会读到过期时间，滑动立刻被当成点击。
        state.lastScrollAt = performance.now();
        if (state.ticking) { return; }
        state.ticking = true;
        window.requestAnimationFrame(onScroll);
      }, { passive: true });

      var pointer = null;
      window.addEventListener("pointerdown", function (event) {
        if (!event.isPrimary) { return; }
        pointer = {
          x: event.clientX,
          y: event.clientY,
          at: performance.now(),
          scrollY: window.scrollY,
          blocked: (performance.now() - state.lastScrollAt) < 260
        };
      }, true);

      window.addEventListener("pointerup", function (event) {
        if (!pointer) { return; }
        var start = pointer;
        pointer = null;
        if (start.blocked) { return; }
        var dx = Math.abs(event.clientX - start.x);
        var dy = Math.abs(event.clientY - start.y);
        var held = performance.now() - start.at;
        if (dx > 10 || dy > 10 || held > 320) { return; }
        if (Math.abs(window.scrollY - start.scrollY) > 1) { return; }
        if (state.selection) { return; }
        var selection = window.getSelection();
        if (selection && !selection.isCollapsed) { return; }
        post({ type: "tap", x: event.clientX, y: event.clientY });
      }, true);

      window.addEventListener("pointercancel", function () { pointer = null; }, true);

      document.addEventListener("selectionchange", function () {
        var selection = window.getSelection();
        state.selection = !!(selection && !selection.isCollapsed);
      });

      document.addEventListener("load", function () { refreshMetrics(); }, true);
      window.addEventListener("resize", function () { refreshMetrics(); });

      function animateTo(target, duration) {
        var start = window.scrollY;
        var delta = target - start;
        if (Math.abs(delta) < 0.5) { return; }
        if (!duration) { window.scrollTo(0, target); return; }
        try {
          window.scrollTo({ top: target, behavior: "smooth" });
        } catch (error) {
          window.scrollTo(0, target);
          return;
        }
        // 平台可能忽略 smooth（Reduce Motion / 无合成器）：等一小段，若位移
        // 完全没发生就直接落位，别让一次翻页点击变成没反应。
        window.setTimeout(function () {
          if (Math.abs(window.scrollY - start) < 2) { window.scrollTo(0, target); }
        }, Math.min(Math.max(duration * 0.45, 90), 160));
      }

      function pageStep(direction) {
        var viewport = window.innerHeight;
        var maximum = Math.max(document.documentElement.scrollHeight - viewport, 0);
        var step = Math.max(viewport * 0.88, 1);
        var target = Math.min(Math.max(window.scrollY + direction * step, 0), maximum);
        if (Math.abs(target - window.scrollY) < 0.5) {
          post({ type: "page-boundary", direction: direction });
          return;
        }
        animateTo(target, 280);
      }

      function scrollToFlat(flat, animated) {
        var element = elementForFlat(flat);
        if (!element) {
          post({ type: "scroll-miss", flat: flat });
          return;
        }
        var rect = element.getBoundingClientRect();
        var target = Math.max(rect.top + window.scrollY - topInset(), 0);
        if (Math.abs(target - window.scrollY) >= 4) {
          animateTo(target, animated ? 320 : 0);
        }
        state.visible = -1;
        window.requestAnimationFrame(onScroll);
        post({ type: "scroll-applied", flat: flat });
      }

      /// 回到文档顶端。换书/首次进书时调用：WKWebView 可能被复用，
      /// 上一本书的滚动位置会带进来，表现就是「第一次打开却看不见章标题」。
      function resetScroll() {
        state.visible = -1;
        window.scrollTo(0, 0);
        window.requestAnimationFrame(onScroll);
      }

      function highlight(flat) {
        if (state.highlightEl) {
          state.highlightEl.classList.remove("hl");
          state.highlightEl = null;
        }
        if (flat < 0) { return; }
        var element = content.querySelector('[data-flat="' + flat + '"]');
        if (!element) { return; }
        element.classList.add("hl");
        state.highlightEl = element;
      }

      window.__reader = {
        setStyle: setStyle,
        setContent: setContent,
        scrollToFlat: scrollToFlat,
        pageStep: pageStep,
        highlight: highlight,
        refreshMetrics: refreshMetrics,
        resetScroll: resetScroll,
        state: state
      };

      post({ type: "ready" });
    })();
    </script>
    </body>
    </html>
    """#
}
