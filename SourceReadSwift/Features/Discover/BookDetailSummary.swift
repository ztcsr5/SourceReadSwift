import SwiftUI

/// Identity and word count are already in BookDetailHeader; do not repeat them.
struct BookDetailSummary: View {
    var detail: BookDetail?
    var fallbackIntro: String? = nil
    /// Detail loads do not always carry a book URL (some rules only return a
    /// TOC); fall back to the result URL that opened this screen.
    var fallbackBookURL: String? = nil
    @State private var expanded = false
    @AppMotion private var motion

    private var metadata: [String] {
        guard let detail else { return [] }
        return [detail.kind?.nilIfEmpty, detail.status?.nilIfEmpty,
                detail.updateTime?.nilIfEmpty.map { "更新 \($0)" }].compactMap { $0 }
    }

    private var effectiveIntro: String? {
        Self.preferredIntro(detail: detail?.intro, fallback: fallbackIntro)
    }

    /// Preserve the fullest synopsis received for this edition across metadata refreshes.
    static func preferredIntro(detail: String?, fallback: String?) -> String? {
        let cleanDetail = sanitizeIntro(detail)
        let cleanFallback = sanitizeIntro(fallback)
        guard let d = cleanDetail, !d.isEmpty else { return cleanFallback }
        guard let f = cleanFallback, !f.isEmpty else { return d }
        // Pick the richer synopsis if detail intro is truncated or significantly shorter
        if (f.count > d.count + 20) || (d.hasSuffix("...") && f.count > d.count) || (d.hasSuffix("…") && f.count > d.count) {
            return f
        }
        return d.count >= f.count ? d : f
    }

    /// 判断简介是否被源站截断（以省略号收尾）。超过 40 字才提示，避免把一句
    /// 本来就很短的简介当成截断；后缀列表由解析层统一提供。
    static func looksTruncated(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 40 else { return false }
        return BookDetailParser.endsWithExcerptSuffix(trimmed)
    }

    var body: some View {
        let intro = effectiveIntro
        let latest = detail?.latestChapter?.nilIfEmpty
        if intro != nil || !metadata.isEmpty || latest != nil {
            VStack(alignment: .leading, spacing: 9) {
                if let intro {
                    Text("简介").font(.subheadline.weight(.semibold))
                    Text(intro)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .lineLimit(intro.count > 100 && !expanded ? 5 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("bookDetail.synopsis")
                    if intro.count > 100 {
                        Button {
                            withAnimation(motion.animation(.expansion)) { expanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(expanded ? "收起简介" : "展开全部简介")
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .tint(AppTheme.accent)
                        .frame(minHeight: 44)
                        .buttonStyle(AppPressStyle())
                        .accessibilityIdentifier("bookDetail.toggleSynopsis")
                    }
                    // C 方案：源站本身就只给了半截简介时，给一个「去原网页看」的出口，
                    // 只对以省略号结尾的文本显示，避免正常简介也挂个链接。
                    if Self.looksTruncated(intro),
                       let raw = detail?.bookUrl?.nilIfEmpty ?? fallbackBookURL?.nilIfEmpty,
                       let url = URL(string: raw), url.scheme?.hasPrefix("http") == true {
                        Link(destination: url) {
                            Label("查看原网页", systemImage: "safari")
                        }
                        .font(.caption.weight(.semibold))
                        .tint(AppTheme.accent)
                        .accessibilityIdentifier("bookDetail.openSourcePage")
                    }
                }
                if !metadata.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(metadata.indices, id: \.self) { index in
                            Text(metadata[index]).font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
                if let latest {
                    Text("最新：\(latest)").font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .podcastCard()
        }
    }

    static func sanitizeIntro(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&emsp;", with: "　")
        text = text.replacingOccurrences(of: "&ensp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = decodeHTMLEntities(text)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func decodeHTMLEntities(_ input: String) -> String {
        var result = input
        let pattern = "&#(x?[0-9a-fA-F]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let nsString = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length)).reversed()
        for match in matches {
            let codeString = nsString.substring(with: match.range(at: 1))
            let code: UInt32?
            if codeString.hasPrefix("x") || codeString.hasPrefix("X") {
                code = UInt32(codeString.dropFirst(), radix: 16)
            } else {
                code = UInt32(codeString, radix: 10)
            }
            if let code, let scalar = UnicodeScalar(code) {
                result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
            }
        }
        return result
    }
}
