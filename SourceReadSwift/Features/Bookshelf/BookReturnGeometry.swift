import SwiftUI
import UIKit

/// Converts the actual mounted jacket rectangle, never an assumed screen ratio.
enum BookReturnGeometry {
    @MainActor static func alignment(of anchor: UIView, in controller: UIViewController) -> CGRect? {
        guard anchor.isDescendant(of: controller.view) else { return nil }
        let rect = anchor.convert(anchor.bounds, to: controller.view)
        guard !rect.isEmpty, !rect.isNull, rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite else { return nil }
        return rect
    }
}

private struct BookReturnAnchorKey: EnvironmentKey {
    static let defaultValue: ((UIView) -> Void)? = nil
}

extension EnvironmentValues {
    var bookReturnAnchor: ((UIView) -> Void)? {
        get { self[BookReturnAnchorKey.self] }
        set { self[BookReturnAnchorKey.self] = newValue }
    }
}

struct BookReturnAnchorProbe: UIViewRepresentable {
    let onLayout: (UIView) -> Void

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }
    func updateUIView(_ view: AnchorView, context: Context) { view.onLayout = onLayout }

    final class AnchorView: UIView {
        var onLayout: ((UIView) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onLayout?(self) }
        }
    }
}
