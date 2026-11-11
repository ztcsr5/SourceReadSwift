import SwiftUI
import Combine
import UIKit

/// A presentation ends only after UIKit commits its return, never on a speculative disappear.
@MainActor
final class ReaderNavigationSession: ObservableObject {
    enum Phase: Equatable { case opening, reading, returning, closed }
    let id = UUID()
    let bookID: String?
    @Published private(set) var phase: Phase = .opening
    @Published private(set) var isContentReady = false
    var allowsReturn = true
    private(set) var webViewIdentities: Set<ObjectIdentifier> = []
    private(set) var shellLoads = 0
    private(set) var hasPresentedContent = false
    private(set) var openingStage = "created"
    private(set) var readerAppearances = 0
    private(set) var isOpeningManaged = false
    private(set) var didReceiveReady = false
    private(set) var zoomDecisionCount = 0
    private(set) var lastZoomDecision = "none"
    private(set) var contentTapCount = 0
    private(set) var menuTapCount = 0
    private(set) var lastMenuState = false
    private(set) var openingCursor = "unset"
    private(set) var renderedMenuState = false
    private(set) var renderedTransitionState = true
    private(set) var renderedScrollTarget: Int?
    private(set) var bridgeEvents: [String] = []
    private var exitActions: [UUID: () -> Void] = [:]
    private var selectChapterAction: ((Int) -> Void)?

    init(bookID: String? = nil) { self.bookID = bookID }

    func registerChapterSelection(_ action: @escaping (Int) -> Void) { selectChapterAction = action }

    @discardableResult
    func selectChapter(_ index: Int) -> Bool {
        guard phase != .closed, index >= 0, let selectChapterAction else { return false }
        selectChapterAction(index)
        return true
    }

    func didAppear() {
        guard phase != .closed, phase != .reading else { return }
        phase = .reading
    }

    func willLeave() {
        guard phase != .closed, phase != .returning else { return }
        phase = .returning
    }

    func registerExit(owner: UUID, action: @escaping () -> Void) {
        guard phase != .closed else { return }
        exitActions[owner] = action
    }

    func recordWebView(_ view: AnyObject) { webViewIdentities.insert(ObjectIdentifier(view)) }
    func recordShellLoad() { shellLoads += 1 }
    func recordPresentedContent() {
        hasPresentedContent = true
        recordReadyReceipt()
    }
    func recordOpeningStage(_ stage: String) { openingStage = stage }
    func recordAppearance(managed: Bool) {
        readerAppearances += 1
        isOpeningManaged = managed
    }
    func recordReadyReceipt() {
        guard phase != .closed else { return }
        didReceiveReady = true
        if !isContentReady { isContentReady = true }
    }

    func recordZoomDecision(location: CGPoint, willBegin: Bool, accepted: Bool) {
        zoomDecisionCount += 1
        lastZoomDecision = "x=\(Int(location.x));begin=\(willBegin);allowed=\(allowsReturn);accepted=\(accepted)"
    }
    func recordContentTap() { contentTapCount += 1 }
    func recordMenuState(_ visible: Bool) { menuTapCount += 1; lastMenuState = visible }
    func recordOpeningCursor(requested: Int?, resolved: Int) {
        openingCursor = "requested=\(requested.map(String.init) ?? "nil");resolved=\(resolved)"
    }

    func recordRenderedState(menu: Bool, transitioning: Bool, target: Int?) {
        renderedMenuState = menu
        renderedTransitionState = transitioning
        renderedScrollTarget = target
    }

    func recordBridgeEvent(_ event: String) {
        guard bridgeEvents.last != event else { return }
        bridgeEvents.append(event)
        if bridgeEvents.count > 12 { bridgeEvents.removeFirst() }
    }

    var renderingEvidence: String {
        "renderedMenu=\(renderedMenuState);transition=\(renderedTransitionState);target=\(renderedScrollTarget.map(String.init) ?? "nil");bridge=\(bridgeEvents.joined(separator: ","))"
    }

    func commitExit() {
        guard phase != .closed else { return }
        phase = .closed
        let actions = Array(exitActions.values)
        exitActions.removeAll()
        selectChapterAction = nil
        actions.forEach { $0() }
        NavigationTrace.shared.mark("reader-session", "committed \(id.uuidString.prefix(8))")
    }
}

struct ReaderNavigationEvidence: UIViewRepresentable {
    let session: ReaderNavigationSession
    func makeUIView(context: Context) -> EvidenceView { EvidenceView() }
    func updateUIView(_ view: EvidenceView, context: Context) { view.session = session }

    final class EvidenceView: UIView {
        weak var session: ReaderNavigationSession?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = true
            accessibilityIdentifier = "reader.navigationEvidence"
            accessibilityLabel = "阅读会话"
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Created programmatically") }
        override var accessibilityValue: String? {
            get {
                guard let session else { return "closed" }
                return "session=\(session.id.uuidString);phase=\(session.phase);web=\(session.webViewIdentities.count);loads=\(session.shellLoads);presented=\(session.hasPresentedContent)"
            }
            set {}
        }
        override var accessibilityLabel: String? {
            get {
                guard let session else { return "阅读会话已关闭" }
                let target = window.flatMap { $0.hitTest(CGPoint(x: $0.bounds.midX, y: $0.bounds.height * 0.42), with: nil) }
                var hitPath: [String] = []
                var ancestor = target
                while let view = ancestor, hitPath.count < 10 {
                    hitPath.append(String(describing: type(of: view)))
                    ancestor = view.superview
                }
                return "stage=\(session.openingStage);appearances=\(session.readerAppearances);managed=\(session.isOpeningManaged);readyReceipt=\(session.didReceiveReady);zoomChecks=\(session.zoomDecisionCount);\(session.lastZoomDecision);taps=\(session.contentTapCount);menus=\(session.menuTapCount);menu=\(session.lastMenuState);hit=\(hitPath.joined(separator: ">"));\(session.openingCursor);\(session.renderingEvidence)"
            }
            set {}
        }
    }
}

private struct NativeReaderSessionKey: EnvironmentKey {
    static let defaultValue: ReaderNavigationSession? = nil
}

private struct ReaderNavigationTransitionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nativeReaderSession: ReaderNavigationSession? {
        get { self[NativeReaderSessionKey.self] }
        set { self[NativeReaderSessionKey.self] = newValue }
    }
    var readerNavigationIsTransitioning: Bool {
        get { self[ReaderNavigationTransitionKey.self] }
        set { self[ReaderNavigationTransitionKey.self] = newValue }
    }
}

/// Refresh the final-position closure without publishing from SwiftUI's update pass.
struct ReaderNativeLifecycleBridge: UIViewControllerRepresentable {
    let session: ReaderNavigationSession?
    let allowsReturn: Bool
    let onExit: () -> Void
    var onSelectChapter: ((Int) -> Void)? = nil
    var renderedMenu = false
    var transitioning = false
    var scrollTarget: Int? = nil

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        session?.allowsReturn = allowsReturn
        if let session { session.registerExit(owner: session.id, action: onExit) }
        if let onSelectChapter { session?.registerChapterSelection(onSelectChapter) }
        session?.recordRenderedState(menu: renderedMenu, transitioning: transitioning, target: scrollTarget)
    }

    final class Controller: UIViewController {
        let owner = UUID()
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }
    }
}
