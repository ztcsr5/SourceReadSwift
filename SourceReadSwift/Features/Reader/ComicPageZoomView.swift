import SwiftUI
import UIKit

/// UIKit owns the pinch, inertia and panning. At fit size, only the parent pages.
struct ComicPageZoomView: UIViewRepresentable {
    let image: UIImage
    let reducesMotion: Bool
    var onFitTap: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ComicZoomScrollView {
        let view = ComicZoomScrollView(frame: .zero)
        let coordinator = context.coordinator
        view.delegate = coordinator
        coordinator.installGestures(on: view)
        return view
    }

    func updateUIView(_ view: ComicZoomScrollView, context: Context) {
        context.coordinator.onFitTap = onFitTap
        context.coordinator.reducesMotion = reducesMotion
        view.setImage(image)
    }

    static func dismantleUIView(_ view: ComicZoomScrollView, coordinator: Coordinator) {
        coordinator.restoreParentPaging()
        view.delegate = nil
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onFitTap: ((CGFloat) -> Void)?
        var onZoomChanged: ((Bool) -> Void)?
        var reducesMotion = false
        private weak var suspendedParent: UIScrollView?
        private var parentWasScrollEnabled = false
        private var isZoomGestureActive = false

        func installGestures(on view: ComicZoomScrollView) {
            let single = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
            double.numberOfTapsRequired = 2
            single.require(toFail: double)
            view.addGestureRecognizer(single)
            view.addGestureRecognizer(double)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ComicZoomScrollView)?.artwork
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ComicZoomScrollView)?.recenterArtwork()
            let isZoomed = scrollView.zoomScale > 1.01
            if isZoomed || isZoomGestureActive { suspendParentPaging(of: scrollView) }
            else { restoreParentPaging() }
            onZoomChanged?(isZoomed)
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isZoomGestureActive = true
            suspendParentPaging(of: scrollView)
            onZoomChanged?(true)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isZoomGestureActive = false
            if scale <= 1.01 { restoreParentPaging() }
            onZoomChanged?(scale > 1.01)
        }

        private func suspendParentPaging(of scrollView: UIScrollView) {
            guard suspendedParent == nil else { return }
            var ancestor = scrollView.superview
            while let candidate = ancestor {
                if let parent = candidate as? UIScrollView, parent.isPagingEnabled {
                    parentWasScrollEnabled = parent.isScrollEnabled
                    suspendedParent = parent
                    parent.isScrollEnabled = false
                    return
                }
                ancestor = candidate.superview
            }
        }

        func restoreParentPaging() {
            // Restore the previous state, not an unconditional true: another
            // screen may have deliberately disabled paging before this zoom.
            suspendedParent?.isScrollEnabled = parentWasScrollEnabled
            suspendedParent = nil
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? ComicZoomScrollView, view.zoomScale <= 1.01, view.bounds.width > 0 else { return }
            onFitTap?(gesture.location(in: view).x / view.bounds.width)
        }

        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? ComicZoomScrollView else { return }
            if view.zoomScale > 1.01 {
                view.setZoomScale(1, animated: !reducesMotion)
            } else {
                let point = gesture.location(in: view.artwork)
                let zoom: CGFloat = 2
                let size = CGSize(width: view.bounds.width / zoom, height: view.bounds.height / zoom)
                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                view.zoom(to: rect, animated: !reducesMotion)
            }
        }
    }
}

final class ComicZoomScrollView: UIScrollView {
    let artwork = UIImageView()
    private var fittedSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        minimumZoomScale = 1
        maximumZoomScale = 3.5
        artwork.contentMode = .scaleAspectFit
        artwork.accessibilityLabel = "漫画图片"
        artwork.isAccessibilityElement = true
        addSubview(artwork)
        panGestureRecognizer.isEnabled = false
    }

    required init?(coder: NSCoder) { return nil }

    func setImage(_ image: UIImage) {
        guard artwork.image !== image else { return }
        artwork.image = image
        fittedSize = .zero
        setNeedsLayout()
    }

    func resetImage() {
        setZoomScale(1, animated: false)
        artwork.image = nil
        fittedSize = .zero
        panGestureRecognizer.isEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size.width > 0, bounds.size.height > 0, let image = artwork.image,
              image.size.width > 0, image.size.height > 0 else { return }
        if bounds.size != fittedSize {
            fittedSize = bounds.size
            setZoomScale(1, animated: false)
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            artwork.frame = CGRect(origin: .zero, size: size)
            contentSize = size
            contentOffset = .zero
        }
        recenterArtwork()
    }

    func recenterArtwork() {
        let center = CGPoint(x: max(bounds.width, contentSize.width) / 2, y: max(bounds.height, contentSize.height) / 2)
        if artwork.center != center { artwork.center = center }
        let canPan = zoomScale > 1.01
        if panGestureRecognizer.isEnabled != canPan { panGestureRecognizer.isEnabled = canPan }
        let zoomDescription = "放大 \(Int((zoomScale * 100).rounded()))%"
        if artwork.accessibilityValue != zoomDescription { artwork.accessibilityValue = zoomDescription }
    }
}
