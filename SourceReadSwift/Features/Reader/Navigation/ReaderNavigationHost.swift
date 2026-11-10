import SwiftUI
import UIKit

/// Owns the outer native stack; tab browsing stacks remain inside its stable root controller.
struct ReaderNavigationHost: UIViewControllerRepresentable {
    @EnvironmentObject private var appState: AppState

    func makeUIViewController(context: Context) -> ReaderNavigationController {
        let root = UIHostingController(rootView: AnyView(RootTabView()
            .modifier(ReaderHostingEnvironment(values: context.environment)).environmentObject(appState)))
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        appState.readerNavigation.attach(navigation, appState: appState)
        return navigation
    }

    func updateUIViewController(_ navigation: ReaderNavigationController, context: Context) {
        if let root = navigation.viewControllers.first as? UIHostingController<AnyView> {
            root.rootView = AnyView(RootTabView().modifier(ReaderHostingEnvironment(values: context.environment))
                .environmentObject(appState))
        }
        appState.readerNavigation.updateEnvironment(context.environment)
    }
}

final class ReaderNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { topViewController }
    override var childForStatusBarHidden: UIViewController? { topViewController }
    override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }
}

/// Native presentation callbacks acknowledge completion; UIKit retains the host on cancellation.
final class NativeReaderHostingController: UIHostingController<AnyView> {
    let session: ReaderNavigationSession
    var onClosed: () -> Void = {}

    init(rootView: AnyView, session: ReaderNavigationSession) {
        self.session = session
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("Native readers are created with a navigation session") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.didAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        let isLeaving = isBeingDismissed || isMovingFromParent
        if isLeaving { session.willLeave() }
        super.viewWillDisappear(animated)
        // A settings cover has a different destination; it is not a reader exit.
        guard isLeaving else { return }
        if let transition = transitionCoordinator {
            transition.animate(alongsideTransition: nil) { [weak self] context in
                guard let self else { return }
                if context.isCancelled { self.session.didAppear() }
                else { self.onClosed() }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if session.phase == .returning, transitionCoordinator == nil,
           navigationController == nil, presentingViewController == nil {
            onClosed()
        }
    }
}

private struct ReaderHostedDestination: View {
    @ObservedObject var session: ReaderNavigationSession
    let request: ReaderDestinationRequest
    let close: () -> Void
    @State private var isReady = false
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue

    var body: some View {
        let paper = ReaderOverrideStore.shared.override(for: request.book.id)?.background
            ?? ReaderBackground(rawValue: paperRaw) ?? .paper
        request.makeContent(close)
            .environment(\.nativeReaderSession, session)
            .environment(\.readerUsesBookReturn, true)
            .environment(\.readerOpeningManaged, !isReady)
            .environment(\.readerNavigationIsTransitioning, session.phase != .reading)
            .allowsHitTesting(isReady)
            .accessibilityHidden(!isReady)
            .onPreferenceChange(ReaderOpeningReadyKey.self) { ready in
                if ready, !isReady {
                    session.recordReadyReceipt()
                    isReady = true
                    NavigationTrace.shared.mark("reader-session", "position ready \(session.id.uuidString.prefix(8))")
                }
            }
            .overlay {
                if !isReady {
                    ReaderOpeningStatus(book: request.book, showsWait: true)
                        .overlay(alignment: .topLeading) {
                            Button(action: close) {
                                Image(systemName: "chevron.backward").frame(width: 44, height: 44)
                                    .background(.thinMaterial, in: Circle())
                            }
                            .accessibilityLabel("返回")
                            .accessibilityIdentifier("reader.loadingReturn")
                            .padding(16)
                        }
                }
            }
            .background(paper.color(isNight: paper.isDark).ignoresSafeArea())
            .background(ReaderNativeArrivalObserver())
            .overlay(alignment: .topTrailing) {
                ReaderNavigationEvidence(session: session).frame(width: 1, height: 1)
            }
    }
}

private struct ReaderNativeArrivalObserver: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ReaderBookPassageController {
        let controller = ReaderBookPassageController()
        controller.usesNativeDeskReturn = true
        controller.canPrepareReturn = true
        return controller
    }
    func updateUIViewController(_ controller: ReaderBookPassageController, context: Context) {}
    static func dismantleUIViewController(_ controller: ReaderBookPassageController, coordinator: ()) {
        controller.detachGestureEvidence()
    }
}

extension NativeReaderHostingController {
    static func make(request: ReaderDestinationRequest, session: ReaderNavigationSession,
                     appState: AppState, environment: EnvironmentValues,
                     close: @escaping () -> Void) -> NativeReaderHostingController {
        NativeReaderHostingController(rootView: content(request: request, session: session,
            appState: appState, environment: environment, close: close), session: session)
    }

    static func content(request: ReaderDestinationRequest, session: ReaderNavigationSession,
                        appState: AppState, environment: EnvironmentValues, close: @escaping () -> Void) -> AnyView {
        AnyView(ReaderHostedDestination(session: session, request: request, close: close)
            .modifier(ReaderHostingEnvironment(values: environment)).environmentObject(appState))
    }
}
