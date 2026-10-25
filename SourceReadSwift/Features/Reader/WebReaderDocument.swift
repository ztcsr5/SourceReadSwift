import CoreGraphics
import Foundation
import UIKit

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
            "selectable": selectable
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
        selectable: Bool
    ) -> WebReaderStylePayload {
        let resolvedTop = topInset ?? max(pagePadding + 10, 24)
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
            surfaceColor: WebReaderColor.hex(surfaceColor),
            highlightColor: WebReaderColor.hex(highlightColor),
            accentColor: WebReaderColor.hex(accentColor),
            selectable: selectable
        )
    }
}

/// Builds the JSON body posted into `window.__reader.setContent`.
enum WebReaderContentPayloadBuilder {
    static func payload(sections: [WebReaderSection], showChapterEndBadge: Bool) -> [String: Any] {
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
                let text = Self.strippingLegacyDividerDecoration(trimmed)
                paragraphs.append(["flat": flat, "local": index, "text": text])
            }

            var entry: [String: Any] = [
                "key": section.key,
                "chapter": section.chapterIndex,
                "title": section.title,
                "start": start,
                "titleFlat": titleFlat,
                "first": isFirst,
                "sig": section.contentSignature,
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
    .chapter { display: block; }
    .chapter-title {
      margin: calc(var(--title-gap) * 1.9) calc(var(--side) * -0.32) var(--title-gap);
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
        metrics: [],
        visible: -1,
        highlightEl: null,
        lastScrollAt: 0,
        ticking: false,
        nearTop: false,
        nearBottom: false,
        reachBottom: false,
        selection: false
      };

      function post(message) {
        try {
          var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.reader;
          if (bridge) { bridge.postMessage(message); }
        } catch (error) {}
      }

      function px(value) { return (Math.round(value * 100) / 100) + "px"; }

      function topInset() { return state.style ? state.style.topInset : 0; }

      function setStyle(style) {
        var anchor = captureAnchor();
        state.style = style;
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
          element.textContent = paragraph.text;
          fragment.appendChild(element);
        }
        node.appendChild(fragment);

        if (section.loading) {
          var loading = document.createElement("p");
          loading.className = "chapter-loading";
          loading.textContent = "正在加载本章…";
          node.appendChild(loading);
        }
        if (section.end) {
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
        var rebuilt = false;

        for (var index = 0; index < payload.sections.length; index += 1) {
          var section = payload.sections[index];
          var existing = state.sections[section.key];
          if (existing && existing.getAttribute("data-sig") === section.sig) {
            rebaseSection(existing, section);
            nextSections[section.key] = existing;
          } else {
            nextSections[section.key] = buildSection(section);
            rebuilt = true;
          }
          nextOrder.push(section.key);
        }

        var sameShape = isPrefixPreserved(payload)
          && nextOrder.length >= state.order.length
          && !rebuilt;

        if (sameShape) {
          for (var tail = state.order.length; tail < nextOrder.length; tail += 1) {
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
        restoreAnchor(anchor);
        post({ type: "content-ready", total: payload.total });
        window.requestAnimationFrame(onScroll);
      }

      function refreshMetrics() {
        var nodes = content.querySelectorAll("[data-flat]");
        var list = [];
        list.length = nodes.length;
        for (var index = 0; index < nodes.length; index += 1) {
          var element = nodes[index];
          var rect = element.getBoundingClientRect();
          var section = element.closest("[data-key]");
          list[index] = {
            flat: parseInt(element.getAttribute("data-flat"), 10) || 0,
            local: parseInt(element.getAttribute("data-local"), 10) || 0,
            key: section ? section.getAttribute("data-key") : "",
            top: rect.top + window.scrollY,
            height: Math.max(rect.height, 1)
          };
        }
        list.sort(function (left, right) { return left.top - right.top; });
        state.metrics = list;
      }

      function metricAt(y) {
        var list = state.metrics;
        if (!list.length) { return null; }
        var low = 0;
        var high = list.length - 1;
        var found = -1;
        while (low <= high) {
          var middle = (low + high) >> 1;
          if (list[middle].top <= y) { found = middle; low = middle + 1; }
          else { high = middle - 1; }
        }
        if (found < 0) { return list[0]; }
        return list[found];
      }

      function captureAnchor() {
        if (!state.metrics.length) { return null; }
        var metric = metricAt(window.scrollY + topInset() + 1);
        if (!metric) { return null; }
        var offset = window.scrollY + topInset() + 1 - metric.top;
        return {
          key: metric.key,
          local: metric.local,
          fraction: Math.min(Math.max(offset / metric.height, 0), 1)
        };
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
        if (Math.abs(target - window.scrollY) < 1) { return; }
        window.scrollTo(0, target);
      }

      function elementForFlat(flat) {
        var exact = content.querySelector('[data-flat="' + flat + '"]');
        if (exact) { return exact; }
        var list = state.metrics;
        var best = null;
        var bestFlat = -1;
        for (var index = 0; index < list.length; index += 1) {
          if (list[index].flat <= flat && list[index].flat > bestFlat) {
            bestFlat = list[index].flat;
            best = list[index];
          }
          if (list[index].flat > flat) { break; }
        }
        if (!best) { return null; }
        return content.querySelector('[data-flat="' + best.flat + '"]');
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
          post({ type: "visible", flat: metric.flat });
        }
        var bottom = y + viewport;
        if (height > 0 && bottom >= height - 650) {
          if (!state.nearBottom) { state.nearBottom = true; post({ type: "near-bottom" }); }
        } else if (bottom < height - 900) {
          state.nearBottom = false;
        }
        if (y <= 650) {
          if (!state.nearTop) { state.nearTop = true; post({ type: "near-top" }); }
        } else if (y > 900) {
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
          blocked: (performance.now() - state.lastScrollAt) < 170
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
        if (dx > 8 || dy > 8 || held > 260) { return; }
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
        var comfortable = rect.top >= topInset() - 2 && rect.top <= window.innerHeight * 0.72;
        if (!comfortable) {
          animateTo(target, animated ? 320 : 0);
        }
        state.visible = -1;
        window.requestAnimationFrame(onScroll);
        post({ type: "scroll-applied", flat: flat });
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
        state: state
      };

      post({ type: "ready" });
    })();
    </script>
    </body>
    </html>
    """#
}
