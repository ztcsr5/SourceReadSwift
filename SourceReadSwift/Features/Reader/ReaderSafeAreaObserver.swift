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
        private var pendingInsets: ReaderSafeAreaResolver.Insets?

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
            guard let window else { return }
            let insets = ReaderSafeAreaResolver.Insets(top: window.safeAreaInsets.top,
                                                       bottom: window.safeAreaInsets.bottom)
            guard lastInsets != insets, pendingInsets != insets else { return }
            pendingInsets = insets
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window,
                      self.pendingInsets == insets else { return }
                self.pendingInsets = nil
                self.lastInsets = insets
                self.onChange?(insets)
            }
        }
    }
}
