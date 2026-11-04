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

private struct ReaderNativeReturnAllowedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// One destination-owned cover across TOC lookup, chapter load and reader layout.
private struct ReaderOpeningPresentation: ViewModifier {
    private static let revealDuration = 0.18
    let book: BookshelfBook
    let coverFrame: UIImage?
    let nativeSourceID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readingCoverHandoff) private var incomingCovers
    @AppMotion private var motion
    @State private var didArrive = false
    @State private var isContentReady = false
    @State private var didReveal = false
    @State private var allowsInteractiveReturn = false

    func body(content: Content) -> some View {
        content
            .environment(\.readerOpeningManaged, !didReveal)
            .environment(\.readerUsesBookReturn, true)
            .allowsHitTesting(didReveal)
            .accessibilityHidden(!didReveal)
            .overlay {
                if !didReveal {
                    ReaderOpeningPage(book: book, coverFrame: coverFrame, isWaiting: didArrive)
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
                nativeSourceID: nativeSourceID,
                handoff: incomingCovers,
                allowsAlignment: !motion.reducesMotion,
                allowsInteraction: allowsInteractiveReturn,
                returnSurface: AnyView(ReaderOpeningPage(book: book, coverFrame: coverFrame,
                    isWaiting: false, isReturning: true)
                    .environment(\.readingCoverHandoff, incomingCovers)),
                onArrival: {
                    didArrive = true
                    revealWhenReady()
                }
            ))
            .onPreferenceChange(ReaderOpeningReadyKey.self) { ready in
                isContentReady = ready
                revealWhenReady()
            }
            .onPreferenceChange(ReaderNativeReturnAllowedKey.self) { allowsInteractiveReturn = $0 }
    }

    private func revealWhenReady() {
        guard !didReveal, didArrive, isContentReady else { return }
        withAnimation(motion.reducesMotion ? nil : .easeOut(duration: Self.revealDuration)) {
            didReveal = true
        }
    }
}

extension View {
    /// Keeps the book visible until native navigation and the first real page have arrived.
    @ViewBuilder func readerOpeningPresentation(for book: BookshelfBook?, coverFrame: UIImage? = nil,
                                                nativeSourceID: String? = nil) -> some View {
        if let book { modifier(ReaderOpeningPresentation(book: book, coverFrame: coverFrame, nativeSourceID: nativeSourceID)) } else { self }
    }

    /// Report actual reader readiness, or an actionable error that must replace the cover.
    func readerOpeningContentReady(_ ready: Bool = true) -> some View {
        preference(key: ReaderOpeningReadyKey.self, value: ready)
    }

    func readerOpeningAllowsNativeReturn(_ allowed: Bool) -> some View {
        preference(key: ReaderNativeReturnAllowedKey.self, value: allowed)
    }
}

private struct ReaderOpeningArrivalProbe: UIViewControllerRepresentable {
    let canPrepareReturn: Bool
    let nativeSourceID: String?
    let handoff: ReadingCoverHandoff?
    let allowsAlignment: Bool
    let allowsInteraction: Bool
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
        controller.restoreNativeReturn()
    }

    private func update(_ controller: ReaderBookPassageController) {
        controller.onArrival = onArrival
        controller.nativeSourceID = nativeSourceID
        controller.coverHandoff = handoff
        controller.allowsNativeAlignment = allowsAlignment
        controller.allowsNativeInteraction = allowsInteraction
        let surface = returnSurface
        controller.makeReturnSurface = { [weak controller] in
            AnyView(surface.environment(\.bookReturnAnchor, { [weak controller] anchor in
                controller?.updateReturnAnchor(anchor)
            }))
        }
        controller.canPrepareReturn = canPrepareReturn
        controller.prepareNativeReturnIfPossible()
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
    @Environment(\.bookReturnAnchor) private var returnAnchor
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue
    private var paper: ReaderBackground { ReaderBackground(rawValue: paperRaw) ?? .white }

    var body: some View {
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
            .background {
                if isReturning, let returnAnchor { BookReturnAnchorProbe(onLayout: returnAnchor) }
            }
            VStack(spacing: 8) {
                Text(book.title).font(.system(.title2, design: .serif).weight(.regular))
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
            Group {
                if isWaiting {
                    ProgressView(chapterTitle == nil ? "正在恢复阅读位置" : "正在加载正文")
                        .font(.caption).accessibilityIdentifier("reader.openingProgress")
                } else { Color.clear }
            }.frame(height: 20)
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
