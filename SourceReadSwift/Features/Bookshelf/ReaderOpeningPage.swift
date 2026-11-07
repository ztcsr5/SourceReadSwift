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
                    ReaderOpeningStatus(showsWait: didArrive)
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
        withAnimation(motion.reducesMotion ? nil : .easeOut(duration: Self.revealDuration)) {
            didReveal = true
        }
    }
}

/// Editorial gallery-grade literary opening transition screen with ambient light and breathing golden emblem.
private struct ReaderOpeningStatus: View {
    let showsWait: Bool
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue
    @State private var isBreathing = false
    @State private var quoteIndex: Int = {
        Int.random(in: 0..<7)
    }()

    private static let literaryQuotes = [
        "翻开一页，遇见另一个世界。",
        "万卷古今消永昼，一窗昏晓送流年。",
        "字里行间，皆有山海与星辰。",
        "读书随处净土，闭门即是深山。",
        "与其喧嚣中奔波，不如在书里小坐片刻。",
        "世间万物皆有回响，开卷即见远方。",
        "且听风吟，静候墨香。"
    ]

    var body: some View {
        let paper = ReaderBackground(rawValue: paperRaw) ?? .white
        let paperColor = paper.color(isNight: paper.isDark)
        let textColor = paper.textColor(isNight: paper.isDark)

        ZStack {
            paperColor.ignoresSafeArea()

            // Soft radial ambient illumination behind the brand emblem
            RadialGradient(
                colors: [textColor.opacity(paper.isDark ? 0.08 : 0.04), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 260
            )
            .ignoresSafeArea()

            if showsWait {
                VStack(spacing: 28) {
                    // Breathing master brand mark with golden aura
                    PaperBetweenMark(size: 62)
                        .shadow(color: Color(red: 1.0, green: 0.72, blue: 0.15).opacity(0.28), radius: 18, x: 0, y: 6)
                        .scaleEffect(isBreathing ? 1.03 : 0.97)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isBreathing)

                    // Refined literary typography
                    VStack(spacing: 12) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 14, weight: .light, design: .serif))
                            .foregroundStyle(textColor.opacity(0.28))

                        Text(Self.literaryQuotes[quoteIndex])
                            .font(.system(size: 16, weight: .medium, design: .serif))
                            .foregroundStyle(textColor.opacity(0.88))
                            .multilineTextAlignment(.center)
                            .lineSpacing(7)
                            .tracking(1.2)
                            .padding(.horizontal, 36)

                        Capsule()
                            .fill(textColor.opacity(0.12))
                            .frame(width: 30, height: 1.5)
                            .padding(.top, 4)

                        Text("纸 间 · 浸 润 墨 香")
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .foregroundStyle(textColor.opacity(0.36))
                            .tracking(3.5)
                    }

                    // Refined loading capsule
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AppTheme.accent)
                            .frame(width: 5, height: 5)
                            .scaleEffect(isBreathing ? 1.25 : 0.75)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isBreathing)

                        Text("正在翻开篇章…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.55))
                            .tracking(1.2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(textColor.opacity(0.04))
                            .overlay(Capsule().strokeBorder(textColor.opacity(0.08), lineWidth: 0.6))
                    )
                    .accessibilityIdentifier("reader.openingProgress")
                }
                .padding(24)
                .transition(.opacity)
                .onAppear {
                    isBreathing = true
                }
            }
        }
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
