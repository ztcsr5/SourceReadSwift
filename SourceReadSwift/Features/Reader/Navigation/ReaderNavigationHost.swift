import SwiftUI
import UIKit

/// Owns the outer native stack; tab browsing stacks remain inside its stable root controller.
struct ReaderNavigationHost: UIViewControllerRepresentable {
    @EnvironmentObject private var appState: AppState
    final class Coordinator {
        var environment: ReaderHostingEnvironment?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> ReaderNavigationController {
        let environment = ReaderHostingEnvironment(values: context.environment)
        context.coordinator.environment = environment
        let root = UIHostingController(rootView: AnyView(RootTabView()
            .modifier(environment).environmentObject(appState)))
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        appState.readerNavigation.attach(navigation, appState: appState)
        appState.readerNavigation.updateEnvironment(context.environment)
        return navigation
    }

    func updateUIViewController(_ navigation: ReaderNavigationController, context: Context) {
        let environment = ReaderHostingEnvironment(values: context.environment)
        guard context.coordinator.environment != environment else { return }
        context.coordinator.environment = environment
        // 不在此重建 RootTabView 的 rootView（否则任何环境脉冲都会触发整颗主页重载）；
        // 仅将最新环境同步给可能挂起的 Reader 宿主。
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !isBeingDismissed, !isMovingFromParent else { return }
        if let transition = transitionCoordinator {
            transition.animate(alongsideTransition: nil) { [weak self] context in
                guard let self, !context.isCancelled else { return }
                self.session.didAppear()
            }
        } else {
            session.didAppear()
        }
    }

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
            transition.notifyWhenInteractionChanges { [weak self] context in
                guard let self, context.isCancelled else { return }
                self.session.didAppear()
            }
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

    /// A parked controller is offscreen but still owns its document. Re-presenting
    /// it must restore the reading phase before the push settles, otherwise the
    /// reader tree keeps its "transitioning" state and the system edge gesture
    /// refuses to begin.
    func prepareForRepresentation() {
        setParked(false)
        session.resumeForReuse()
        session.didAppear()
    }

    /// A returned reader keeps its live view tree for one book. UIKit may hold
    /// that tree in the window until the next push, so an offscreen reader must
    /// stop advertising itself: VoiceOver and UI automation were still finding
    /// a reader the user had already left.
    func setParked(_ isParked: Bool) {
        guard isViewLoaded else { return }
        view.accessibilityElementsHidden = isParked
        view.isUserInteractionEnabled = !isParked
    }
}

private struct ReaderHostedDestination: View {
    @ObservedObject var session: ReaderNavigationSession
    let request: ReaderDestinationRequest
    let close: () -> Void
    private var isReady: Bool { session.isContentReady }
    @ObservedObject private var verification = VerificationCodeCoordinator.shared
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue

    var body: some View {
        let paper = ReaderOverrideStore.shared.override(for: request.book.id)?.background
            ?? ReaderBackground(rawValue: paperRaw) ?? .paper
        request.makeContent(close)
            .environment(\.nativeReaderSession, session)
            .environment(\.readerUsesBookReturn, true)
            .environment(\.readerOpeningManaged, false)
            .environment(\.readerNavigationIsTransitioning, session.phase != .reading)
            .onPreferenceChange(ReaderOpeningReadyKey.self) { ready in
                if ready, !isReady {
                    session.recordReadyReceipt()
                    NavigationTrace.shared.mark("reader-session", "position ready \(session.id.uuidString.prefix(8))")
                }
            }
            .background(paper.color(isNight: paper.isDark).ignoresSafeArea())
            .background(ReaderNativeArrivalObserver(session: session))
            .overlay(alignment: .topTrailing) {
                ReaderNavigationEvidence(session: session).frame(width: 1, height: 1)
            }
            .sheet(item: verificationRequest) { request in
                VerificationCodeSheet(request: request,
                    onSubmit: { verification.submit(id: request.id, code: $0) },
                    onCancel: { verification.cancel(id: request.id) })
            }
    }

    private var verificationRequest: Binding<VerificationCodeRequest?> {
        Binding(get: {
            let isUnitTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                || NSClassFromString("XCTestCase") != nil
            return isUnitTest ? nil : verification.request
        }, set: { verification.request = $0 })
    }
}

private struct ReaderNativeArrivalObserver: UIViewControllerRepresentable {
    let session: ReaderNavigationSession

    func makeUIViewController(context: Context) -> ReaderBookPassageController {
        let controller = ReaderBookPassageController()
        controller.usesNativeDeskReturn = true
        controller.canPrepareReturn = true
        controller.onInteractivePop = { [weak session] in session?.recordInteractivePopBegin() }
        return controller
    }
    func updateUIViewController(_ controller: ReaderBookPassageController, context: Context) {}
    static func dismantleUIViewController(_ controller: ReaderBookPassageController, coordinator: ()) {
        controller.detachGestureEvidence()
    }
}

extension NativeReaderHostingController {
    static func make(request: ReaderDestinationRequest, session: ReaderNavigationSession,
                     appState: AppState, environment: ReaderHostingEnvironment,
                     close: @escaping () -> Void) -> NativeReaderHostingController {
        NativeReaderHostingController(rootView: content(request: request, session: session,
            appState: appState, environment: environment, close: close), session: session)
    }

    static func content(request: ReaderDestinationRequest, session: ReaderNavigationSession,
                        appState: AppState, environment: ReaderHostingEnvironment, close: @escaping () -> Void) -> AnyView {
        AnyView(ReaderHostedDestination(session: session, request: request, close: close)
            .modifier(environment).environmentObject(appState))
    }
}
