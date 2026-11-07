import SwiftUI

/// Identity and word count are already in BookDetailHeader; do not repeat them.
struct BookDetailSummary: View {
    var detail: BookDetail?
    var fallbackIntro: String? = nil
    @State private var expanded = false
    @AppMotion private var motion

    private var metadata: [String] {
        guard let detail else { return [] }
        return [detail.kind?.nilIfEmpty, detail.status?.nilIfEmpty,
                detail.updateTime?.nilIfEmpty.map { "更新 \($0)" }].compactMap { $0 }
    }

    private var effectiveIntro: String? {
        Self.sanitizeIntro(detail?.intro?.nilIfEmpty ?? fallbackIntro)
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
                        .lineLimit(intro.count > 90 && !expanded ? 4 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if intro.count > 90 {
                        Button(expanded ? "收起简介" : "展开完整简介") {
                            withAnimation(motion.animation(.expansion)) { expanded.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                        .tint(AppTheme.accent)
                        .frame(minHeight: 36)
                        .buttonStyle(AppPressStyle())
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
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
