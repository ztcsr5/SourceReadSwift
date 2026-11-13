import SwiftUI
import UIKit

/// Native zoom asks for the current, visible source again on return. Never cache its rectangle.
@MainActor
final class ReaderZoomSources {
    static let shared = ReaderZoomSources()
    private final class Entry {
        weak var view: UIView?
        weak var lastWindow: UIWindow?
        init(_ view: UIView) {
            self.view = view
            self.lastWindow = view.window
        }
    }
    private var entries: [String: [Entry]] = [:]
    #if DEBUG
    /// How many distinct host views have ever been registered per id. A cover
    /// that is rebuilt during a return shows up here as a rising count; the
    /// "封面空白后重新加载" report is exactly that, not a下载 problem.
    private var creations: [String: Int] = [:]
    #endif

    func register(_ view: UIView, id: String) {
        var sources = entries[id, default: []].filter { $0.view != nil }
        if let entry = sources.first(where: { $0.view === view }) {
            if let window = view.window { entry.lastWindow = window }
        } else {
            sources.append(Entry(view))
            #if DEBUG
            creations[id, default: 0] += 1
            #endif
        }
        entries[id] = sources
    }

    #if DEBUG
    /// `created/alive` for one id, e.g. `continue|abc=1/1`.
    func identityEvidence(id: String) -> String {
        let alive = entries[id, default: []].filter { $0.view != nil }.count
        return "\(creations[id, default: 0])/\(alive)"
    }

    func identityEvidenceForAllIDs() -> String {
        entries.keys.sorted().map { $0 + "=" + identityEvidence(id: $0) }.joined(separator: ",")
    }

    /// UIKit hides the zoom source for the duration of the transition and is
    /// supposed to restore it afterwards. The user report "封面位置空白，回来
    /// 才重新加载" is exactly a source that stayed hidden or at alpha 0, which
    /// `created/alive` alone cannot see. Read the live view, after the fact.
    func visibilityEvidenceForAllIDs() -> String {
        entries.keys.sorted().compactMap { id -> String? in
            guard let view = entries[id]?.last(where: { $0.view != nil })?.view else { return nil }
            let hidden = view.isHidden
            let alpha = String(format: "%.2f", view.alpha)
            let attached = view.superview != nil
            return "\(id)=hidden=\(hidden),alpha=\(alpha),attached=\(attached)"
        }.joined(separator: "|")
    }
    #endif

    func source(id: String?, window: UIWindow?) -> UIView? {
        guard let id, let window else { return nil }
        var retained: UIView?
        for entry in entries[id, default: []].reversed() {
            guard let view = entry.view, view.superview != nil,
                  view.bounds.width > 1, view.bounds.height > 1 else { continue }
            if let sourceWindow = view.window {
                entry.lastWindow = sourceWindow
                if sourceWindow === window && window.bounds.intersects(view.convert(view.bounds, to: window)) {
                    return view
                }
            } else if retained == nil, entry.lastWindow === window {
                // Pop can ask before reinserting the retained root, but never use another window's source.
                retained = view
            }
        }
        return retained
    }
}

/// Hosts the actual cover so UIKit can hide and restore precisely that source during its zoom.
struct ReaderZoomSource<Content: View>: UIViewControllerRepresentable {
    let id: String
    let content: Content

    final class Coordinator {
        var lastEnvironment: ReaderHostingEnvironment?
        var registeredID: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let environment = ReaderHostingEnvironment(values: context.environment)
        context.coordinator.lastEnvironment = environment
        context.coordinator.registeredID = id
        let host = UIHostingController(rootView: AnyView(content.modifier(environment)))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        ReaderZoomSources.shared.register(host.view, id: id)
        return host
    }

    func updateUIViewController(_ host: UIHostingController<AnyView>, context: Context) {
        let currentEnv = ReaderHostingEnvironment(values: context.environment)
        let environment = (context.coordinator.lastEnvironment == currentEnv)
            ? (context.coordinator.lastEnvironment ?? currentEnv)
            : currentEnv
        context.coordinator.lastEnvironment = environment
        host.rootView = AnyView(content.modifier(environment))
        if context.coordinator.registeredID != id || host.view.window != nil {
            context.coordinator.registeredID = id
            ReaderZoomSources.shared.register(host.view, id: id)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: UIHostingController<AnyView>,
                     context: Context) -> CGSize? {
        uiViewController.sizeThatFits(in: CGSize(width: proposal.width ?? UIView.layoutFittingExpandedSize.width,
                                                height: proposal.height ?? UIView.layoutFittingExpandedSize.height))
    }
}

extension View {
    /// Registers a concrete visual source while preserving the surrounding SwiftUI layout.
    func readerZoomSource(_ id: String) -> some View {
        ReaderZoomSource(id: id, content: self)
    }
}
