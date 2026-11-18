import UIKit

/// A full-page cylindrical fold. One shared bitmap backs all strips; dragging only moves layers.
@MainActor
final class ReaderCurlSurface {
    static let foldAnimationKey = "reader.curl.fold"
    private static let stripCount = 24

    private struct Capture {
        let key: String
        let size: CGSize
        let scale: CGFloat
        let image: UIImage
    }
    private struct StripPlacement {
        let centerX: CGFloat
        let transform: CGAffineTransform
        let isBack: Bool
        let shadeOpacity: Float
    }

    private let overlay = UIView()
    private var strips: [UIView] = []
    private var shades: [UIView] = []
    private var captures: [ObjectIdentifier: Capture] = [:]
    private weak var sheet: UIView?
    private var configuredTurning: ObjectIdentifier?
    private var configuredDirection = 0
    private var configuredBackFaces = [Bool?](repeating: nil, count: ReaderCurlSurface.stripCount)
    private var direction = 1
    private var progress: CGFloat = 0
    private var animationGeneration = 0
    private var animationCompletion: (() -> Void)?
    var isAnimating: Bool { animationCompletion != nil }

    init() {
        overlay.isUserInteractionEnabled = false
        overlay.accessibilityElementsHidden = true
        // Fixed tessellation bounds CPU and layer cost independently of chapter length.
        for _ in 0..<Self.stripCount {
            let strip = UIView()
            strip.isUserInteractionEnabled = false
            let shade = UIView()
            shade.isUserInteractionEnabled = false
            strip.addSubview(shade)
            overlay.addSubview(strip)
            strips.append(strip)
            shades.append(shade)
        }
    }

    func warm(page: UIView, key: String) {
        let size = page.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let scale = page.window?.screen.scale ?? page.traitCollection.displayScale
        let identity = ObjectIdentifier(page)
        if let cached = captures[identity], cached.key == key, cached.size == size, cached.scale == scale { return }
        let capture = PerformanceSignpost.begin("reader.curl.capture")
        defer { PerformanceSignpost.end("reader.curl.capture", id: capture) }
        page.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = page.isOpaque
        let alpha = page.alpha
        let isHidden = page.isHidden
        let transform = page.transform
        var image: UIImage!
        UIView.performWithoutAnimation {
            page.alpha = 1
            page.isHidden = false
            page.transform = .identity
            let canDrawHierarchy = page.window != nil && !isHidden && alpha > 0.01
            image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                if canDrawHierarchy, page.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false) {
                    return
                }
                page.layer.render(in: context.cgContext)
            }
            page.alpha = alpha
            page.isHidden = isHidden
            page.transform = transform
        }
        captures[identity] = Capture(key: key, size: size, scale: scale, image: image)
    }

    func retain(pages: [UIView]) {
        let identities = Set(pages.map { ObjectIdentifier($0) })
        captures = captures.filter { identities.contains($0.key) }
    }

    func prepare(direction: Int, in container: UIView, pages: [UIView?]) {
        self.direction = direction < 0 ? -1 : 1
        UIView.performWithoutAnimation {
            apply(translation: 0, in: container, pages: pages)
        }
    }

    func apply(translation: CGFloat, in container: UIView, pages: [UIView?]) {
        guard pages.count == 3, let current = pages[1] else { return }
        if translation != 0 { direction = translation < 0 ? 1 : -1 }
        let width = max(container.bounds.width, 1)
        // The current page is always the sheet that curls. The adjacent page
        // is only the paper revealed beneath it; capturing the previous page
        // on a reverse turn makes it visible before the finger moves.
        let turning = current
        let beneath = direction > 0 ? pages[2] : pages[0]
        let unused = direction > 0 ? pages[0] : pages[2]
        let key = turning.accessibilityIdentifier ?? ""
        let scale = turning.window?.screen.scale ?? turning.traitCollection.displayScale
        let turningID = ObjectIdentifier(turning)
        let needsSetup = configuredTurning != turningID
            || configuredDirection != direction
            || overlay.bounds.size != container.bounds.size
        guard let capture = captures[turningID], capture.key == key,
              capture.size == turning.bounds.size, capture.scale == scale else {
            // A first finger frame must never pay for layout and rasterization.
            if needsSetup || overlay.superview != nil {
                reset(pages: pages)
                overlay.bounds = container.bounds
                configuredTurning = turningID
                configuredDirection = direction
                unused?.alpha = 0
                beneath?.isUserInteractionEnabled = false
                beneath?.accessibilityElementsHidden = true
                unused?.isUserInteractionEnabled = false
                unused?.accessibilityElementsHidden = true
            }
            beneath?.transform = CGAffineTransform(translationX: translation + (direction > 0 ? width : -width), y: 0)
            turning.transform = CGAffineTransform(translationX: translation, y: 0)
            return
        }
        if needsSetup || sheet !== turning || overlay.superview !== container {
            unused?.alpha = 0
            beneath?.alpha = 1
            for page in pages {
                page?.transform = .identity
                page?.layer.shadowOpacity = 0
                page?.isUserInteractionEnabled = page === current
                page?.accessibilityElementsHidden = page !== current
            }
            if let beneath, container.subviews.first !== beneath { container.sendSubviewToBack(beneath) }
            if overlay.superview !== container { container.addSubview(overlay) }
            else if container.subviews.last !== overlay { container.bringSubviewToFront(overlay) }
            turning.alpha = 0
            configuredTurning = turningID
            configuredDirection = direction
            if sheet !== turning || overlay.bounds.size != container.bounds.size {
                sheet = turning
                overlay.frame = container.bounds
                configureStrips(image: capture.image, size: container.bounds.size)
            }
            for index in strips.indices { strips[index].layer.zPosition = CGFloat(direction * index) }
        }
        progress = min(abs(translation) / width, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let paper = backPaper(for: turning)
        placeStrips(width: width, progress: progress) { index, placement in
            setPlacement(placement, at: index, paper: paper)
        }
        CATransaction.commit()
    }

    /// Sample the same cylinder as the gesture; interpolating directly to a flat endpoint collapses the whole sheet.
    func animate(to translation: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) -> Bool {
        let width = overlay.bounds.width
        guard let sheet, overlay.superview != nil, width > 1 else { return false }
        let setup = PerformanceSignpost.begin("reader.curl.setup")
        defer { PerformanceSignpost.end("reader.curl.setup", id: setup) }
        let target = min(abs(translation) / width, 1)
        let steps = max(1, Int(ceil(abs(target - progress) * CGFloat(Self.stripCount))))
        let frames: [[StripPlacement]] = (0...steps).map { step in
            let sample = progress + (target - progress) * CGFloat(step) / CGFloat(steps)
            var placements: [StripPlacement] = []
            placements.reserveCapacity(strips.count)
            placeStrips(width: width, progress: sample) { _, placement in placements.append(placement) }
            return placements
        }
        let paper = backPaper(for: sheet)
        let ink = UIColor.black.cgColor
        // Core Animation copies the group on add; all strips can use the same timing.
        let timeline = CAAnimationGroup()
        timeline.duration = duration
        timeline.timingFunction = CAMediaTimingFunction(name: progress == 0 ? .easeInEaseOut : .easeOut)
        if let screen = overlay.window?.screen,
           let cadence = FrameRateCoordinator.preferredRange(maximumFramesPerSecond: screen.maximumFramesPerSecond) {
            timeline.preferredFrameRateRange = cadence
        }
        progress = target
        animationGeneration &+= 1
        let generation = animationGeneration
        animationCompletion = completion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.finishAnimation()
        }
        for index in strips.indices {
            let path = frames.map { $0[index] }
            setPlacement(frames[steps][index], at: index, paper: paper)
            Self.addTracks([
                ("position.x", path.map { NSNumber(value: Double($0.centerX)) }),
                ("transform", path.map { NSValue(caTransform3D: CATransform3DMakeAffineTransform($0.transform)) })
            ], to: strips[index].layer, timeline: timeline)
            Self.addTracks([
                ("backgroundColor", path.map { $0.isBack ? paper : ink }),
                ("opacity", path.map { NSNumber(value: $0.shadeOpacity) })
            ], to: shades[index].layer, timeline: timeline)
        }
        CATransaction.commit()
        return true
    }

    private static func addTracks(_ tracks: [(String, [Any])], to layer: CALayer, timeline: CAAnimationGroup) {
        timeline.animations = tracks.map { path, values in
            let track = CAKeyframeAnimation(keyPath: path)
            track.values = values
            track.duration = timeline.duration
            return track
        }
        layer.add(timeline, forKey: foldAnimationKey)
    }

    private func placeStrips(width: CGFloat, progress: CGFloat, apply: (Int, StripPlacement) -> Void) {
        let stripWidth = width / CGFloat(strips.count)
        let radius = width * 0.10 * sin(.pi * progress)
        var left = projectedFoldPosition(x: 0, width: width, progress: progress, radius: radius)
        for index in strips.indices {
            let right = projectedFoldPosition(x: CGFloat(index + 1) * stripWidth, width: width,
                progress: progress, radius: radius)
            let isBack = right.x < left.x
            let depth = (left.depth + right.depth) / 2
            let transform = CGAffineTransform(scaleX: (right.x - left.x) / stripWidth,
                                               y: 1 - depth / max(width * 8, 1))
            apply(index, StripPlacement(centerX: (left.x + right.x) / 2, transform: transform,
                isBack: isBack, shadeOpacity: Float(isBack ? 0.88 : min(depth / width, 0.18))))
            left = right
        }
    }

    private func backPaper(for page: UIView) -> CGColor {
        (page.isOpaque ? page.backgroundColor ?? .systemBackground : .systemBackground)
            .resolvedColor(with: page.traitCollection).cgColor
    }

    private func setPlacement(_ placement: StripPlacement, at index: Int, paper: CGColor) {
        let layer = strips[index].layer
        layer.setAffineTransform(placement.transform)
        layer.position = CGPoint(x: placement.centerX, y: overlay.bounds.midY)
        let shade = shades[index].layer
        if configuredBackFaces[index] != placement.isBack {
            shade.backgroundColor = placement.isBack ? paper : UIColor.black.cgColor
            configuredBackFaces[index] = placement.isBack
        }
        shade.opacity = placement.shadeOpacity
    }

    private func projectedFoldPosition(x: CGFloat, width: CGFloat, progress: CGFloat, radius: CGFloat) -> (x: CGFloat, depth: CGFloat) {
        guard direction > 0 else {
            let mirrored = Self.foldPosition(x: width - x, width: width, progress: progress, radius: radius)
            return (width - mirrored.x, mirrored.depth)
        }
        return Self.foldPosition(x: x, width: width, progress: progress, radius: radius)
    }

    /// Project a paper coordinate onto a cylinder, continuing flat on its reverse side.
    static func foldPosition(x: CGFloat, width: CGFloat, progress: CGFloat) -> (x: CGFloat, depth: CGFloat) {
        let progress = min(max(progress, 0), 1)
        let radius = width * 0.10 * sin(.pi * progress)
        return foldPosition(x: x, width: width, progress: progress, radius: radius)
    }

    private static func foldPosition(x: CGFloat, width: CGFloat, progress: CGFloat, radius: CGFloat) -> (x: CGFloat, depth: CGFloat) {
        let fold = width * (1 - progress)
        guard x > fold else { return (x, 0) }
        guard radius > 0.001 else { return (2 * fold - x, 0) }
        let arc = min((x - fold) / radius, .pi)
        let tail = max(x - fold - .pi * radius, 0)
        return (fold + radius * sin(arc) - tail, radius * (1 - cos(arc)))
    }

    func reset(pages: [UIView?]) {
        cancelAnimation()
        overlay.removeFromSuperview()
        sheet = nil
        configuredTurning = nil
        configuredDirection = 0
        configuredBackFaces = [Bool?](repeating: nil, count: strips.count)
        clearStripContents()
        for strip in strips {
            strip.transform = .identity
            strip.layer.setAffineTransform(.identity)
        }
        resetShadeState()
        for page in pages {
            page?.alpha = 1
            page?.transform = .identity
            page?.layer.setAffineTransform(.identity)
            page?.layer.transform = CATransform3DIdentity
            page?.layer.shadowOpacity = 0
            page?.isUserInteractionEnabled = true
            page?.accessibilityElementsHidden = false
        }
    }

    func finishAnimation() {
        guard let completion = animationCompletion else { return }
        cancelAnimation()
        completion()
    }

    func cancelAnimation() {
        guard isAnimating else { return }
        animationCompletion = nil
        animationGeneration &+= 1
        for surface in strips + shades { surface.layer.removeAnimation(forKey: Self.foldAnimationKey) }
    }

    func invalidate() {
        captures.removeAll()
        reset(pages: [])
    }

    private func clearStripContents() {
        for strip in strips { strip.layer.contents = nil }
    }

    private func resetShadeState() {
        for shade in shades {
            shade.alpha = 1
            shade.layer.opacity = 0
            shade.layer.backgroundColor = nil
        }
    }

    private func configureStrips(image: UIImage, size: CGSize) {
        let fraction = 1 / CGFloat(strips.count)
        for index in strips.indices {
            let strip = strips[index]
            strip.layer.setAffineTransform(.identity)
            strip.transform = .identity
            strip.bounds = CGRect(x: 0, y: 0, width: size.width * fraction, height: size.height)
            strip.layer.contents = image.cgImage
            strip.layer.contentsScale = image.scale
            strip.layer.contentsRect = CGRect(x: CGFloat(index) * fraction, y: 0, width: fraction, height: 1)
            shades[index].frame = strip.bounds
            shades[index].alpha = 1
            shades[index].layer.opacity = 0
        }
    }
}
