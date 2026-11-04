import SwiftUI
import UIKit

/// Retains the decoded pipeline frame and its URL together across a native handoff.
struct NativeReadingCoverFrame {
    let url: URL
    let image: UIImage
}

/// The visible cover itself is the UIKit source, not a second hidden screenshot.
struct NativeReadingCover: UIViewRepresentable {
    let image: UIImage
    let sourceID: String
    let handoff: ReadingCoverHandoff
    let cornerRadius: CGFloat

    func makeUIView(context: Context) -> CoverImageView {
        let view = CoverImageView()
        view.isUserInteractionEnabled = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: CoverImageView, context: Context) {
        if view.image !== image { view.image = image }
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.bind(to: handoff, sourceID: sourceID)
    }

    static func dismantleUIView(_ view: CoverImageView, coordinator: ()) {
        view.unbind()
    }

    final class CoverImageView: UIImageView {
        private weak var handoff: ReadingCoverHandoff?
        private var sourceID: String?
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }

        func bind(to next: ReadingCoverHandoff, sourceID nextID: String) {
            if handoff === next, sourceID == nextID { return }
            unbind()
            handoff = next
            sourceID = nextID
            next.registerNativeCover(self, for: nextID)
        }

        func unbind() {
            if let sourceID { handoff?.removeNativeCover(self, for: sourceID) }
            handoff = nil
            sourceID = nil
        }
    }
}
