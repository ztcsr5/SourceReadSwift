import SwiftUI
import UIKit

private struct ReaderOpeningManagedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
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

/// One destination-owned cover across TOC lookup, chapter load and reader layout.
private struct ReaderOpeningPresentation: ViewModifier {
    private static let revealDuration = 0.18
    let book: BookshelfBook
    let coverFrame: UIImage?
    @Environment(\.dismiss) private var dismiss
    @AppMotion private var motion
    @State private var didArrive = false
    @State private var isContentReady = false
    @State private var didReveal = false

    func body(content: Content) -> some View {
        content
            .environment(\.readerOpeningManaged, !didReveal)
            .allowsHitTesting(didReveal)
            .accessibilityHidden(!didReveal)
            .overlay {
                if !didReveal {
                    ReaderOpeningPage(book: book, coverFrame: coverFrame)
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
            .background(ReaderOpeningArrivalProbe {
                didArrive = true
                revealWhenReady()
            })
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

extension View {
    /// Keeps the book visible until native navigation and the first real page have arrived.
    @ViewBuilder func readerOpeningPresentation(for book: BookshelfBook?, coverFrame: UIImage? = nil) -> some View {
        if let book { modifier(ReaderOpeningPresentation(book: book, coverFrame: coverFrame)) } else { self }
    }

    /// Report actual reader readiness, or an actionable error that must replace the cover.
    func readerOpeningContentReady(_ ready: Bool = true) -> some View {
        preference(key: ReaderOpeningReadyKey.self, value: ready)
    }
}

private struct ReaderOpeningArrivalProbe: UIViewControllerRepresentable {
    let onArrival: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onArrival = onArrival
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onArrival = onArrival
    }

    final class Controller: UIViewController {
        var onArrival: () -> Void = {}

        override func loadView() {
            let probe = UIView()
            probe.isUserInteractionEnabled = false
            view = probe
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            DispatchQueue.main.async { [weak self] in self?.onArrival() }
        }
    }
}

/// Real book identity remains visible while the gateway restores its actual chapter.
struct ReaderOpeningPage: View {
    let book: BookshelfBook
    var chapterTitle: String? = nil
    var coverFrame: UIImage? = nil
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue
    private var paper: ReaderBackground { ReaderBackground(rawValue: paperRaw) ?? .white }
    var body: some View {
        VStack(spacing: 16) {
            BookJacket {
                if let coverFrame {
                    Image(uiImage: coverFrame).resizable().scaledToFill()
                        .frame(width: 84, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    AsyncBookCover(urlString: book.coverURL, width: 84, height: 120,
                        baseURLString: book.bookURL, sourceURLString: book.sourceURL, title: book.title)
                }
            }
            Text(book.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .lineLimit(2)
            ProgressView(chapterTitle == nil ? "正在恢复阅读位置" : "正在加载正文")
                .font(.caption)
                .accessibilityIdentifier("reader.openingProgress")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(paper.textColor(isNight: paper.isDark))
        .background(paper.color(isNight: paper.isDark).ignoresSafeArea())
        .environment(\.colorScheme, paper.isDark ? .dark : .light)
    }
}
