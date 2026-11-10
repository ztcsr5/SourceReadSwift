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

private struct ReaderOpeningReadyKey: PreferenceKey {
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
        content
            .environment(\.readerOpeningManaged, !didReveal)
            .environment(\.readerUsesBookReturn, true)
            .allowsHitTesting(didReveal)
            .accessibilityHidden(!didReveal)
            .overlay {
                if !didReveal {
                    ReaderOpeningStatus(book: book, showsWait: didArrive)
                        .toolbar(.hidden, for: .navigationBar)
                        .overlay(alignment: .topLeading) {
                            if didArrive {
                                Button { dismiss() } label: {
                                    Image(systemName: "chevron.backward")
                                        .font(.body.weight(.semibold))
                                        .frame(width: 44, height: 44)
                                        .background(.thinMaterial, in: Circle())
                                }
                                .buttonStyle(BookOpenPressStyle())
                                .accessibilityLabel("返回")
                                .padding(16)
                            }
                        }
                        .transition(.opacity)
                }
            }
            .background(ReaderOpeningArrivalProbe(
                canPrepareReturn: didReveal,
                usesNativeDeskReturn: usesNativeDeskReturn,
                returnSurface: AnyView(ReaderOpeningPage(book: book, coverFrame: coverFrame,
                    isWaiting: false, isReturning: true)
                    .environment(\.readingCoverHandoff, incomingCovers)),
                onArrival: {
                    NavigationTrace.shared.mark("open", "开场页落地")
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
        NavigationTrace.shared.mark("open", "正文已就绪，揭开开场页")
        withAnimation(motion.reducesMotion ? nil : .easeOut(duration: Self.revealDuration)) {
            didReveal = true
        }
    }
}

/// Keeps the destination recognisable while its actual saved position is prepared.
/// Static type and paragraph scaffolding share the reader's paper; no logo or timer delays entry.
struct ReaderOpeningStatus: View {
    let book: BookshelfBook
    let showsWait: Bool
    var chapterTitle: String? = nil
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue

    private var context: String {
        let chapter = (chapterTitle ?? book.currentChapterTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !chapter.isEmpty { return chapter }
        return book.currentParagraphIndex == nil ? "准备开始阅读" : "回到上次阅读的位置"
    }

    var body: some View {
        let paper = ReaderOverrideStore.shared.override(for: book.id)?.background
            ?? ReaderBackground(rawValue: paperRaw) ?? .paper
        let ink = paper.textColor(isNight: paper.isDark)
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(book.title)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reader.openingTitle")
                        if !book.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(book.author).font(.subheadline).foregroundStyle(ink.opacity(0.7))
                        }
                    }
                    Rectangle().fill(ink.opacity(0.16)).frame(height: 1)
                    Text(context).font(.headline).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(0..<7) { line in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(ink.opacity(0.07))
                                .frame(maxWidth: line == 3 || line == 6 ? geometry.size.width * 0.56 : .infinity)
                                .frame(height: 8)
                        }
                    }
                    .accessibilityHidden(true)
                    Text(book.currentParagraphIndex == nil ? "正在准备正文" : "正在恢复阅读位置")
                        .font(.footnote).foregroundStyle(ink.opacity(0.7))
                        .opacity(showsWait ? 1 : 0)
                        .accessibilityHidden(!showsWait)
                        .accessibilityIdentifier("reader.openingProgress")
                }
                .padding(.horizontal, 32)
                .padding(.top, 80)
                .padding(.bottom, 32)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(ink)
        .background { paper.color(isNight: paper.isDark).ignoresSafeArea() }
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
        preference(key: ReaderOpeningReadyKey.self, value: ready)
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
