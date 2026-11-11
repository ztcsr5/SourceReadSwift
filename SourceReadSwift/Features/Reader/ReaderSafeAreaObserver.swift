import SwiftUI
import UIKit

/// Samples the reader's own window outside SwiftUI body evaluation.
struct ReaderSafeAreaObserver: UIViewRepresentable {
    let onChange: (ReaderSafeAreaResolver.Insets) -> Void

    func makeUIView(context: Context) -> ObserverView { ObserverView() }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        view.sampleInsets()
    }

    final class ObserverView: UIView {
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
            let insets = ReaderSafeAreaResolver.Insets(top: current.top, bottom: current.bottom)
            guard insets != lastInsets else { return }
            lastInsets = insets
            onChange?(insets)
        }
    }
}
