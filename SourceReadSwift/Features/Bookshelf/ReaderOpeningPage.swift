import SwiftUI
import UIKit

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

/// 覆盖层需要读取这个信号判断正文是否真的就位，因此不再是 private。
struct ReaderOpeningReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// A destination-owned readiness gate, separate from the book's formal title page.
private struct ReaderOpeningPresentation: ViewModifier {
    private static let revealDuration = 0.18
    let book: BookshelfBook
    let coverFrame: UIImage?
    let usesDeskHero: Bool
    let usesSystemReturnSurface: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readingCoverHandoff) private var incomingCovers
    @AppMotion private var motion
    @State private var didArrive = false
    @State private var isContentReady = false
    @State private var didReveal = false

    private var usesNativeDeskReturn: Bool {
        if usesSystemReturnSurface { return true }
        if #available(iOS 18.0, *) { return usesDeskHero }
        return false
    }

    func body(content: Content) -> some View {
        // 不再盖开场占位页。
        //
        // 实测：白卡 + 假骨架在 0.75–1.25s 占满屏幕，然后 0.18s 淡出，
        // 这 0.18s 里占位页与真正的正文同时可见 —— 「第壹章」出现两次、
        // 正文互相穿透，是整段里最丑的一帧，且没有任何设计价值。
        //
        // 现在直接让阅读层自己铺纸面背景，正文就绪后一次出现。
        // 到达探针与 ready 信号保留，因为返回云面与交互解锁还依赖它们。
        content
            .environment(\.readerOpeningManaged, false)
            .environment(\.readerUsesBookReturn, true)
            .allowsHitTesting(true)
            .background(ReaderOpeningArrivalProbe(
                canPrepareReturn: true,
                usesNativeDeskReturn: usesNativeDeskReturn,
                returnSurface: AnyView(ReaderOpeningPage(book: book, coverFrame: coverFrame,
                    isWaiting: false, isReturning: true)
                    .environment(\.readingCoverHandoff, incomingCovers)),
                onArrival: {
                    NavigationTrace.shared.mark("open", "阅读层落地")
                    didArrive = true
                    revealWhenReady()
                }
            ))
            .onPreferenceChange(ReaderOpeningReadyKey.self) { ready in
                isContentReady = ready
                revealWhenReady()
            }
    }

    private func revealWhenReady() {
        guard !didReveal, didArrive, isContentReady else { return }
        NavigationTrace.shared.mark("open", "正文已就绪")
        didReveal = true
    }
}

/// Shows the actual book and restore operation while the positioned reader is prepared.
struct ReaderOpeningStatus: View {
    let book: BookshelfBook
    let showsWait: Bool
    var chapterTitle: String? = nil
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue

    var body: some View {
        let paper = ReaderOverrideStore.shared.override(for: book.id)?.background
            ?? ReaderBackground(rawValue: paperRaw) ?? .paper
        let ink = paper.textColor(isNight: paper.isDark)
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 48)
            Image(systemName: "book.closed")
                .font(.system(size: 32, weight: .regular))
                .accessibilityHidden(true)
            Text(book.title)
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reader.openingTitle")
            if !book.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(book.author).font(.subheadline).foregroundStyle(ink.opacity(0.72))
            }
            Rectangle().fill(ink.opacity(0.16)).frame(height: 1)
            if let chapter = chapterTitle ?? book.currentChapterTitle, !chapter.isEmpty {
                Text(chapter).font(.headline)
            }
            HStack(spacing: 12) {
                if showsWait { ProgressView().tint(ink) }
                else { Color.clear.frame(width: 20, height: 20) }
                Text(book.currentParagraphIndex == nil ? "正在准备正文" : "正在恢复阅读位置")
                    .font(.subheadline)
                    .opacity(showsWait ? 1 : 0)
            }
            .accessibilityIdentifier("reader.openingProgress")
            Spacer(minLength: 48)
            Text("纸间 · 阅读")
                .font(.caption).foregroundStyle(ink.opacity(0.65))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(ink)
        .background(paper.color(isNight: paper.isDark).ignoresSafeArea())
        .environment(\.colorScheme, paper.isDark ? .dark : .light)
    }
}

extension View {
    /// Prevents an unpositioned page from becoming visible during native navigation.
    @ViewBuilder func readerOpeningPresentation(for book: BookshelfBook?, coverFrame: UIImage? = nil,
                                                usesDeskHero: Bool = false, usesSystemReturnSurface: Bool = false) -> some View {
        if let book { modifier(ReaderOpeningPresentation(book: book, coverFrame: coverFrame,
            usesDeskHero: usesDeskHero, usesSystemReturnSurface: usesSystemReturnSurface)) } else { self }
    }

    /// Report actual reader readiness, or an actionable error that must replace the cover.
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

private struct ReaderOpeningArrivalProbe: UIViewControllerRepresentable {
    let canPrepareReturn: Bool
    let usesNativeDeskReturn: Bool
    let returnSurface: AnyView
    let onArrival: () -> Void

    func makeUIViewController(context: Context) -> ReaderBookPassageController {
        let controller = ReaderBookPassageController()
        update(controller)
        return controller
    }

    func updateUIViewController(_ controller: ReaderBookPassageController, context: Context) {
        update(controller)
    }

    static func dismantleUIViewController(_ controller: ReaderBookPassageController, coordinator: ()) {
        controller.removeReturnSurface()
        controller.detachGestureEvidence()
    }

    private func update(_ controller: ReaderBookPassageController) {
        controller.onArrival = onArrival
        controller.usesNativeDeskReturn = usesNativeDeskReturn
        controller.canPrepareReturn = canPrepareReturn
        controller.makeReturnSurface = { returnSurface }
    }
}

/// One book identity for arrival and return; readiness is never delayed for its animation.
struct ReaderOpeningPage: View {
    let book: BookshelfBook
    var chapterTitle: String? = nil
    var coverFrame: UIImage? = nil
    var isWaiting = true
    var isReturning = false
    @AppMotion private var motion
    @Environment(\.readingCoverHandoff) private var incomingCovers
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue
    @MainActor private var paper: ReaderBackground {
        ReaderOverrideStore.shared.override(for: book.id)?.background
            ?? ReaderBackground(rawValue: paperRaw) ?? .paper
    }

    var body: some View {
        if isWaiting && !isReturning {
            ReaderOpeningStatus(book: book, showsWait: true, chapterTitle: chapterTitle)
        } else {
            returnPage
        }
    }

    private var returnPage: some View {
        VStack(spacing: 20) {
            EditorialBookJacket(height: 190, palette: .resolve(theme: AppVisualTheme.current), stance: .detail) {
                if let coverFrame = coverFrame ?? incomingCovers?.frame(for: book) {
                    Image(uiImage: coverFrame).resizable().scaledToFill()
                        .frame(width: 142, height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else if isReturning {
                    BookCoverPlaceholder(title: book.title, height: 190)
                        .frame(width: 142, height: 190)
                } else {
                    AsyncBookCover(urlString: book.coverURL, width: 142, height: 190,
                        baseURLString: book.bookURL, sourceURLString: book.sourceURL,
                        title: book.title, prefersDeskRaster: true, cornerRadius: 3)
                }
            }
            VStack(spacing: 8) {
                Text(book.title).font(.title2.weight(.regular))
                    .multilineTextAlignment(.center).lineLimit(2)
                if !book.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(book.author).font(.caption).opacity(0.65).lineLimit(1)
                }
                if !isReturning {
                    Text(ReadingDeskContent.contextLine(for: book))
                        .font(.caption).opacity(0.65).lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .opacity(isWaiting || isReturning ? 1 : 0)
            .offset(y: isWaiting || isReturning || motion.reducesMotion ? 0 : 8)
            .animation(isReturning ? nil : motion.arrivalAnimation(stage: 1), value: isWaiting)
            Color.clear.frame(height: 20)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(paper.textColor(isNight: paper.isDark))
        .background {
            paper.color(isNight: paper.isDark).ignoresSafeArea()
        }
        .environment(\.colorScheme, paper.isDark ? .dark : .light)
    }
}
