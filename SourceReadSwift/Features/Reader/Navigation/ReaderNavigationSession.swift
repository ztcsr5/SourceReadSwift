import SwiftUI
import Combine
import UIKit

/// A presentation ends only after UIKit commits its return, never on a speculative disappear.
@MainActor
final class ReaderNavigationSession: ObservableObject {
    enum Phase: Equatable { case opening, reading, returning, closed }
    let id = UUID()
    @Published private(set) var phase: Phase = .opening
    var allowsReturn = true
    private(set) var webViewIdentities: Set<ObjectIdentifier> = []
    private(set) var shellLoads = 0
    private(set) var hasPresentedContent = false
    private var exitActions: [UUID: () -> Void] = [:]

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
    func recordPresentedContent() { hasPresentedContent = true }

    func commitExit() {
        guard phase != .closed else { return }
        phase = .closed
        let actions = Array(exitActions.values)
        exitActions.removeAll()
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

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        session?.allowsReturn = allowsReturn
        if let session { session.registerExit(owner: session.id, action: onExit) }
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
