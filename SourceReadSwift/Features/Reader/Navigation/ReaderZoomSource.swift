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

    func register(_ view: UIView, id: String) {
        var sources = entries[id, default: []].filter { $0.view != nil }
        if let entry = sources.first(where: { $0.view === view }) {
            if let window = view.window { entry.lastWindow = window }
        } else {
            sources.append(Entry(view))
        }
        entries[id] = sources
    }

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

    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let host = UIHostingController(rootView: AnyView(content.modifier(ReaderHostingEnvironment(values: context.environment))))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        ReaderZoomSources.shared.register(host.view, id: id)
        return host
    }

    func updateUIViewController(_ host: UIHostingController<AnyView>, context: Context) {
        host.rootView = AnyView(content.modifier(ReaderHostingEnvironment(values: context.environment)))
        ReaderZoomSources.shared.register(host.view, id: id)
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
