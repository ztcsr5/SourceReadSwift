import SwiftUI
import UIKit

/// Samples the reader's own window outside SwiftUI body evaluation.
struct ReaderSafeAreaObserver: UIViewRepresentable {
    var measuresViewport = false
    let onChange: (ReaderSafeAreaResolver.Insets) -> Void

    func makeUIView(context: Context) -> ObserverView { ObserverView() }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        view.measuresViewport = measuresViewport
        view.sampleInsets()
    }

    final class ObserverView: UIView {
        var measuresViewport = false
        var onChange: ((ReaderSafeAreaResolver.Insets) -> Void)?
        private var lastInsets: ReaderSafeAreaResolver.Insets?
        private var isSampleScheduled = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Created programmatically") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            sampleInsets()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            sampleInsets()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            sampleInsets()
        }

        func sampleInsets() {
            guard window != nil, !isSampleScheduled else { return }
            isSampleScheduled = true
            // Sample after the layout/update cycle, not from a stale window or
            // a transient inset captured before SwiftUI finished laying out.
            DispatchQueue.main.async { [weak self] in self?.publishCurrentInsets() }
        }

        private func publishCurrentInsets() {
            isSampleScheduled = false
            guard let window else { return }
            let current = window.safeAreaInsets
            let insets = measuresViewport
                ? ReaderSafeAreaObserver.viewportInsets(window: window.bounds, safe: current, viewport: convert(bounds, to: window),
                    isPhone: traitCollection.userInterfaceIdiom == .phone)
                : ReaderSafeAreaResolver.Insets(top: current.top, bottom: current.bottom)
            guard insets != lastInsets else { return }
            lastInsets = insets
            onChange?(insets)
        }
    }

    /// Subtract space already reserved by the host instead of adding the notch inset twice.
    static func viewportInsets(window: CGRect, safe: UIEdgeInsets, viewport: CGRect, isPhone: Bool) -> ReaderSafeAreaResolver.Insets {
        guard !viewport.isEmpty, !window.isEmpty else { return .init(top: 0, bottom: 0) }
        var edges = safe
        if isPhone, edges == .zero, window.height > window.width {
            let fallback = ReaderSafeAreaResolver.resolve(windowTop: 0, windowBottom: 0, statusBarHeight: 0, screenSize: window.size)
            edges.top = fallback.top
            edges.bottom = fallback.bottom
        }
        let safeFrame = window.inset(by: edges)
        // A navigation transition can move the whole viewport outside the window; that offset is not a safe area.
        return .init(top: min(edges.top, max(0, safeFrame.minY - viewport.minY)),
                     bottom: min(edges.bottom, max(0, viewport.maxY - safeFrame.maxY)),
                     left: min(edges.left, max(0, safeFrame.minX - viewport.minX)),
                     right: min(edges.right, max(0, viewport.maxX - safeFrame.maxX)))
    }
}
