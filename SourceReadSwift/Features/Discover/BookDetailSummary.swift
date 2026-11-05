import SwiftUI

/// Identity and word count are already in BookDetailHeader; do not repeat them.
struct BookDetailSummary: View {
    let detail: BookDetail
    @State private var expanded = true
    @AppMotion private var motion

    private var metadata: [String] {
        [detail.kind?.nilIfEmpty, detail.status?.nilIfEmpty,
         detail.updateTime?.nilIfEmpty.map { "更新 \($0)" }].compactMap { $0 }
    }

    var body: some View {
        if detail.intro?.nilIfEmpty != nil || !metadata.isEmpty || detail.latestChapter?.nilIfEmpty != nil {
            VStack(alignment: .leading, spacing: 9) {
                if let intro = detail.intro?.nilIfEmpty {
                    Text("简介").font(.subheadline.weight(.semibold))
                    Text(intro).font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                        .lineLimit(intro.count > 60 && !expanded ? 4 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if intro.count > 60 {
                        Button(expanded ? "收起简介" : "展开简介") {
                            withAnimation(motion.animation(.expansion)) { expanded.toggle() }
                        }
                            .font(.caption.weight(.semibold)).tint(AppTheme.accent)
                            .frame(minHeight: 44)
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
                if let latest = detail.latestChapter?.nilIfEmpty {
                    Text("最新：\(latest)").font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .podcastCard()
        }
    }
}
