import UIKit

/// A disposable animation carrier: all scaling stays outside the live reader and original book cover.
final class ReaderSnapshotFlightView: UIView {
    private let page: UIView?
    private let cover: UIView?
    var pageAlpha: CGFloat {
        get { page?.alpha ?? 1 }
        set { page?.alpha = newValue }
    }
    var coverAlpha: CGFloat {
        get { cover?.alpha ?? 0 }
        set { cover?.alpha = newValue }
    }

    init(frame: CGRect, paper: UIColor, page: UIView?, cover: UIView?) {
        self.page = page
        self.cover = cover
        super.init(frame: frame)
        backgroundColor = paper
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        layer.cornerCurve = .continuous
        for surface in [page, cover].compactMap({ $0 }) {
            surface.autoresizingMask = []
            addSubview(surface)
        }
        move(to: frame, cornerRadius: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Created from rendered snapshots") }

    /// Animate the clipping boundary, not the aspect ratio of captured text and artwork.
    func move(to frame: CGRect, cornerRadius: CGFloat) {
        bounds = CGRect(origin: .zero, size: frame.size)
        center = CGPoint(x: frame.midX, y: frame.midY)
        layer.cornerRadius = cornerRadius
        for surface in [page, cover].compactMap({ $0 }) {
            let size = surface.bounds.size
            guard size.width > 0, size.height > 0 else { continue }
            let scale = max(bounds.width / size.width, bounds.height / size.height)
            surface.center = CGPoint(x: bounds.midX, y: bounds.midY)
            surface.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
}
