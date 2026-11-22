import SwiftUI

private struct ReaderBookReturnKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ReaderOpeningManagedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var readerUsesBookReturn: Bool {
        get { self[ReaderBookReturnKey.self] }
        set { self[ReaderBookReturnKey.self] = newValue }
    }

    var readerOpeningManaged: Bool {
        get { self[ReaderOpeningManagedKey.self] }
        set { self[ReaderOpeningManagedKey.self] = newValue }
    }
}

/// 覆盖层/原生路由读取该信号以确认正文就绪，不再渲染任何正文前介绍遮罩或「纸间·阅读」过渡页。
struct ReaderOpeningReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// One visual loading surface for the directory-to-prose handoff.
struct ReaderChapterLoadingSurface: View {
    let bookID: String?
    var chapterTitle: String? = nil
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue

    var body: some View {
        let paper = bookID.flatMap { ReaderOverrideStore.shared.override(for: $0)?.background }
            ?? ReaderBackground(rawValue: paperRaw) ?? .paper
        VStack(spacing: 8) {
            ProgressView().controlSize(.large)
                .accessibilityIdentifier("reader.loadingSpinner")
            Text("正在打开阅读器").font(.headline)
            Text(chapterTitle.map { "正在加载正文 · " + $0 } ?? "正在准备章节目录")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .accessibilityIdentifier("reader.loadingStage")
        }
        .foregroundStyle(paper.textColor(isNight: paper.isDark))
        .tint(paper.textColor(isNight: paper.isDark))
        .padding(AppTheme.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paper.color(isNight: paper.isDark).ignoresSafeArea())
    }
}

extension View {
    func readerOpeningContentReady(_ ready: Bool = true) -> some View {
        modifier(ReaderOpeningReadiness(ready: ready))
    }
}

private struct ReaderOpeningReadiness: ViewModifier {
    let ready: Bool
    @Environment(\.nativeReaderSession) private var session

    func body(content: Content) -> some View {
        content.preference(key: ReaderOpeningReadyKey.self, value: ready)
            .onAppear { if ready { session?.recordReadyReceipt() } }
            .onChange(of: ready) { if $0 { session?.recordReadyReceipt() } }
    }
}
