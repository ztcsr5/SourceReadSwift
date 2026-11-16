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
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        for surface in [page, cover].compactMap({ $0 }) {
            surface.frame = bounds
            surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(surface)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Created from rendered snapshots") }

    static func transform(from bounds: CGRect, to destination: CGRect) -> CGAffineTransform {
        guard bounds.width > 1, bounds.height > 1 else { return .identity }
        return CGAffineTransform(translationX: destination.midX - bounds.midX, y: destination.midY - bounds.midY)
            .scaledBy(x: destination.width / bounds.width, y: destination.height / bounds.height)
    }
}
