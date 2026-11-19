import UIKit

/// Animates mounted neighbouring pages without rebuilding text or decoding images during a turn.
@MainActor
final class ReaderPageRevealSurface {
    private let aperture = UIView()
    private let splitAperture = UIView()
    private let rippleOverlay = UIView()
    private let rippleHaloWave = UIView()
    private let rippleOuterWave = UIView()
    private let rippleMidWave = UIView()
    private let rippleInnerWave = UIView()
    private var rippleRingsActive = false
    private weak var maskedPage: UIView?
    private var isActive = false
    private var direction = 1
    private var configuredCurrent: ObjectIdentifier?
    private var configuredIncoming: ObjectIdentifier?
    private var configuredStyle: CoverPageTurnStyle?

    init() {
        aperture.backgroundColor = .black
        splitAperture.backgroundColor = .black

        rippleOverlay.isUserInteractionEnabled = false
        rippleOverlay.accessibilityElementsHidden = true
        rippleOverlay.backgroundColor = .clear
        rippleOverlay.clipsToBounds = true
        rippleOverlay.isHidden = true

        configureRippleWave(rippleHaloWave, borderWidth: 16,
                            color: UIColor(red: 0.44, green: 0.79, blue: 0.98, alpha: 0.18))
        configureRippleWave(rippleOuterWave, borderWidth: 5.5,
                            color: UIColor(red: 0.42, green: 0.78, blue: 0.96, alpha: 0.48))
        configureRippleWave(rippleMidWave, borderWidth: 2.5,
                            color: UIColor.white.withAlphaComponent(0.78))
        configureRippleWave(rippleInnerWave, borderWidth: 2.0,
                            color: UIColor(red: 0.56, green: 0.86, blue: 1.0, alpha: 0.36))
    }

    private func configureRippleWave(_ wave: UIView, borderWidth: CGFloat, color: UIColor) {
        wave.isUserInteractionEnabled = false
        wave.backgroundColor = .clear
        wave.layer.borderWidth = borderWidth
        wave.layer.borderColor = color.cgColor
        rippleOverlay.addSubview(wave)
    }

    func prepare(direction: Int, style: CoverPageTurnStyle, in container: UIView, pages: [UIView?],
                 origin: CGPoint? = nil) {
        self.direction = direction < 0 ? -1 : 1
        rippleRingsActive = (style == .ripple)
        UIView.performWithoutAnimation {
            apply(style: style, translation: 0, in: container, pages: pages, origin: origin)
        }
    }

    func clearTransientDecorations() {
        rippleRingsActive = false
        rippleOverlay.isHidden = true
    }

    func reset(pages: [UIView?]) {
        guard isActive else { return }
        isActive = false
        rippleRingsActive = false
        rippleOverlay.isHidden = true
        rippleOverlay.removeFromSuperview()
        maskedPage?.mask = nil
        maskedPage = nil
        configuredCurrent = nil
        configuredIncoming = nil
        configuredStyle = nil
        for page in pages {
            page?.alpha = 1
            page?.transform = .identity
            page?.layer.transform = CATransform3DIdentity
            page?.layer.cornerRadius = 0
            page?.layer.shadowOpacity = 0
            if page?.layer.shouldRasterize == true {
                page?.layer.shouldRasterize = false
            }
            page?.isUserInteractionEnabled = true
            page?.accessibilityElementsHidden = false
        }
    }

    func apply(style: CoverPageTurnStyle, translation: CGFloat, in container: UIView, pages: [UIView?],
               origin: CGPoint? = nil) {
        guard pages.count == 3, let current = pages[1] else { return }
        isActive = true
        let width = max(container.bounds.width, 1)
        let height = max(container.bounds.height, 1)
        let progress = min(abs(translation) / width, 1)
        if translation != 0 {
            direction = translation > 0 ? -1 : 1
            if style == .ripple { rippleRingsActive = true }
        }
        let incoming = direction < 0 ? pages[0] : pages[2]
        let outgoingNeighbour = direction < 0 ? pages[2] : pages[0]
        // Reused incoming hosts become the current page after a committed turn.
        // They must never retain a reveal mask, including at the book's last page.
        let incomingID = incoming.map { ObjectIdentifier($0) }
        let needsPageSetup = configuredCurrent != ObjectIdentifier(current)
            || configuredIncoming != incomingID
            || configuredStyle != style
        if needsPageSetup {
            if maskedPage === current { removeMask() }
            if style != .ripple {
                rippleOverlay.isHidden = true
            }
            // A perspective turn uses the layer transform while the other
            // styles use UIView transforms; clear both before a mode/page
            // handoff so transforms never compound across turns.
            for page in [current, incoming, outgoingNeighbour].compactMap({ $0 }) {
                page.transform = .identity
                page.layer.transform = CATransform3DIdentity
                page.layer.cornerRadius = 0
            }
            let scale = max(container.window?.screen.scale ?? UIScreen.main.scale, 2)
            let needsRaster = style == .dissolve || style == .stacked || style == .perspective
                || style == .cube || style == .fan || style == .cardGlide || style == .lens
            for page in [current, incoming].compactMap({ $0 }) {
                if needsRaster {
                    page.layer.rasterizationScale = scale
                    if !page.layer.shouldRasterize { page.layer.shouldRasterize = true }
                } else if page.layer.shouldRasterize {
                    page.layer.shouldRasterize = false
                }
            }
            if outgoingNeighbour?.layer.shouldRasterize == true {
                outgoingNeighbour?.layer.shouldRasterize = false
            }
            current.isUserInteractionEnabled = true
            current.accessibilityElementsHidden = false
            for neighbour in [incoming, outgoingNeighbour] {
                neighbour?.isUserInteractionEnabled = false
                neighbour?.accessibilityElementsHidden = true
            }
            outgoingNeighbour?.alpha = 0
            outgoingNeighbour?.transform = .identity
            current.layer.shadowOpacity = 0
            incoming?.layer.shadowOpacity = 0
            if style == .cardGlide {
                if container.subviews.last !== current { container.bringSubviewToFront(current) }
            } else if let incoming, container.subviews.last !== incoming {
                container.bringSubviewToFront(incoming)
            }
            configuredCurrent = ObjectIdentifier(current)
            configuredIncoming = incomingID
            configuredStyle = style
        }

        switch style {
        case .dissolve:
            removeMask()
            let outScale = 1 - 0.015 * progress
            let inScale = 1.015 - 0.015 * progress
            current.transform = CGAffineTransform(scaleX: outScale, y: outScale)
            current.alpha = 1 - progress * 0.25
            incoming?.transform = CGAffineTransform(scaleX: inScale, y: inScale)
            incoming?.alpha = progress
        case .stacked:
            removeMask()
            current.alpha = 1 - progress * 0.42
            current.layer.cornerCurve = .continuous
            current.layer.cornerRadius = 18 * progress
            current.transform = CGAffineTransform(scaleX: 1 - 0.075 * progress, y: 1 - 0.075 * progress)
                .translatedBy(x: -CGFloat(direction) * width * 0.05 * progress, y: 0)
            incoming?.alpha = 1
            incoming?.layer.cornerCurve = .continuous
            incoming?.layer.cornerRadius = 14 * (1 - progress)
            incoming?.transform = CGAffineTransform(translationX: CGFloat(direction) * width * (1 - progress), y: 0)
        case .ripple:
            current.alpha = 1 - progress * 0.16
            let depthScale = 1 - 0.024 * progress
            current.transform = CGAffineTransform(scaleX: depthScale, y: depthScale)
            incoming?.alpha = 1
            incoming?.transform = .identity
            guard let incoming else {
                removeMask()
                rippleOverlay.isHidden = true
                return
            }
            attachMask(aperture, to: incoming)
            let normX = min(max(origin?.x ?? (direction < 0 ? 0.24 : 0.76), 0.04), 0.96)
            let normY = min(max(origin?.y ?? 0.50, 0.04), 0.96)
            let center = CGPoint(x: width * normX, y: height * normY)
            let maxX = max(center.x, width - center.x)
            let maxY = max(center.y, height - center.y)
            let diameter = hypot(maxX, maxY) * 2.10
            if rippleOverlay.superview !== container {
                container.addSubview(rippleOverlay)
            }
            if container.subviews.last !== rippleOverlay {
                container.bringSubviewToFront(rippleOverlay)
            }
            if rippleOverlay.frame != container.bounds {
                rippleOverlay.frame = container.bounds
            }
            let waves = [rippleHaloWave, rippleOuterWave, rippleMidWave, rippleInnerWave]
            if aperture.bounds.width != diameter || aperture.center != center {
                UIView.performWithoutAnimation {
                    let circleBounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                    let radius = diameter * 0.5
                    aperture.bounds = circleBounds
                    aperture.layer.cornerRadius = radius
                    aperture.center = center
                    for wave in waves {
                        wave.bounds = circleBounds
                        wave.layer.cornerRadius = radius
                        wave.center = center
                    }
                }
            }
            // UIView's transform is interpolated by the same property animator as the page turn.
            let scale = max(progress, 0.0001)
            aperture.transform = CGAffineTransform(scaleX: scale, y: scale)

            let showWaves = rippleRingsActive && (progress > 0 || translation == 0)
            rippleOverlay.isHidden = !showWaves
            if showWaves {
                let fade = max(0, 1 - progress)
                let haloScale = max(progress * 1.05, 0.0001)
                let outerScale = max(progress * 1.005, 0.0001)
                let midScale = max(progress * 0.93, 0.0001)
                let innerScale = max(progress * 0.80, 0.0001)
                rippleHaloWave.transform = CGAffineTransform(scaleX: haloScale, y: haloScale)
                rippleOuterWave.transform = CGAffineTransform(scaleX: outerScale, y: outerScale)
                rippleMidWave.transform = CGAffineTransform(scaleX: midScale, y: midScale)
                rippleInnerWave.transform = CGAffineTransform(scaleX: innerScale, y: innerScale)
                rippleHaloWave.alpha = 0.85 * fade
                rippleOuterWave.alpha = 0.92 * fade
                rippleMidWave.alpha = 0.96 * fade
                rippleInnerWave.alpha = 0.72 * fade
            }
        case .fan:
            removeMask()
            let dir = CGFloat(direction)
            let pivotY = height * 1.45
            let outAngle = -dir * 0.36 * progress
            let outPivot = CGAffineTransform(translationX: 0, y: pivotY)
                .rotated(by: outAngle)
                .translatedBy(x: 0, y: -pivotY)
            current.transform = outPivot.translatedBy(x: -dir * width * 0.32 * progress, y: 0)
            current.layer.cornerCurve = .continuous
            current.layer.cornerRadius = 22 * progress
            current.alpha = 1 - progress * 0.45

            let inAngle = dir * 0.24 * (1 - progress)
            let inScale = 0.96 + 0.04 * progress
            let inPivot = CGAffineTransform(translationX: 0, y: pivotY)
                .rotated(by: inAngle)
                .translatedBy(x: 0, y: -pivotY)
            incoming?.transform = inPivot
                .translatedBy(x: dir * width * 0.28 * (1 - progress), y: 0)
                .scaledBy(x: inScale, y: inScale)
            incoming?.layer.cornerCurve = .continuous
            incoming?.layer.cornerRadius = 22 * (1 - progress)
            incoming?.alpha = 0.55 + 0.45 * progress
        case .cardGlide:
            removeMask()
            let dir = CGFloat(direction)
            let outScale = 1 - 0.05 * progress
            let outAngle = -dir * 0.11 * progress
            current.transform = CGAffineTransform(translationX: -dir * width * 1.06 * progress, y: -18 * progress)
                .rotated(by: outAngle)
                .scaledBy(x: outScale, y: outScale)
            current.layer.cornerCurve = .continuous
            current.layer.cornerRadius = 24 * progress
            current.alpha = 1 - progress * 0.18

            let inScale = 0.935 + 0.065 * progress
            incoming?.transform = CGAffineTransform(translationX: 0, y: 18 * (1 - progress))
                .scaledBy(x: inScale, y: inScale)
            incoming?.layer.cornerCurve = .continuous
            incoming?.layer.cornerRadius = 24 * (1 - progress)
            incoming?.alpha = 0.65 + 0.35 * progress
        case .lens:
            removeMask()
            let dir = CGFloat(direction)
            let outScale = 1 - 0.09 * progress
            current.transform = CGAffineTransform(translationX: -dir * width * 0.14 * progress, y: 0)
                .scaledBy(x: outScale, y: outScale)
            current.layer.cornerCurve = .continuous
            current.layer.cornerRadius = 24 * progress
            current.alpha = 1 - progress * 0.82

            let inScale = 1.065 - 0.065 * progress
            incoming?.transform = CGAffineTransform(translationX: dir * width * 0.22 * (1 - progress), y: 0)
                .scaledBy(x: inScale, y: inScale)
            incoming?.layer.cornerCurve = .continuous
            incoming?.layer.cornerRadius = 24 * (1 - progress)
            incoming?.alpha = progress
        case .verticalSlide:
            removeMask()
            let distance = container.bounds.height * progress
            // A programmatic turn starts at zero; use the committed direction
            // there so the incoming page never jumps to the wrong edge.
            let sign: CGFloat = translation == 0 ? (direction > 0 ? -1 : 1)
                : (translation < 0 ? -1 : 1)
            current.transform = CGAffineTransform(translationX: 0, y: sign * distance)
            incoming?.transform = CGAffineTransform(translationX: 0, y: -sign * container.bounds.height * (1 - progress))
            current.alpha = 1
            incoming?.alpha = 1
        case .parallax:
            removeMask()
            let scale = 1 - 0.032 * progress
            current.transform = CGAffineTransform(translationX: -CGFloat(direction) * width * progress * 0.28, y: 0)
                .scaledBy(x: scale, y: scale)
            current.alpha = 1 - progress * 0.14
            incoming?.transform = CGAffineTransform(translationX: CGFloat(direction) * width * (1 - progress), y: 0)
            incoming?.alpha = 1
        case .wipe, .split:
            current.alpha = 1
            current.transform = .identity
            guard let incoming else { removeMask(); return }
            incoming.alpha = 1
            incoming.transform = .identity
            let mask = style == .split ? splitAperture : aperture
            attachMask(mask, to: incoming)
            let revealWidth = max(width * progress, 0.001)
            mask.bounds = CGRect(origin: .zero, size: CGSize(width: revealWidth, height: container.bounds.height))
            mask.layer.cornerRadius = 0
            if style == .split {
                mask.center = CGPoint(x: width / 2, y: container.bounds.midY)
            } else {
                mask.center = CGPoint(x: direction > 0 ? width - revealWidth / 2 : revealWidth / 2,
                                      y: container.bounds.midY)
            }
            mask.transform = .identity
        case .perspective:
            removeMask()
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / max(width * 1.85, 1)
            let currentAngle = CGFloat(direction) * .pi / 2 * min(progress * 2, 1)
            let incomingAngle = -CGFloat(direction) * .pi / 2 * max(1 - (progress - 0.5) * 2, 0)
            current.layer.transform = progress == 0 ? CATransform3DIdentity : CATransform3DRotate(
                perspective, currentAngle, 0, 1, 0
            )
            incoming?.layer.transform = progress == 1 ? CATransform3DIdentity : CATransform3DRotate(
                perspective, incomingAngle, 0, 1, 0
            )
            current.alpha = progress < 0.5 ? 1 : 0
            incoming?.alpha = progress >= 0.5 ? 1 : 0
        case .cube:
            removeMask()
            let dir = CGFloat(direction)
            let halfWidth = width * 0.5
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / max(width * 2.2, 1)
            // True 90-degree 3D cube rotation around the shared vertical seam.
            let outAngle = -dir * (.pi / 2) * progress
            var outTransform = CATransform3DTranslate(perspective, -dir * width * progress, 0, 0)
            outTransform = CATransform3DTranslate(outTransform, dir * halfWidth, 0, 0)
            outTransform = CATransform3DRotate(outTransform, outAngle, 0, 1, 0)
            outTransform = CATransform3DTranslate(outTransform, -dir * halfWidth, 0, 0)
            current.layer.transform = progress == 0 ? CATransform3DIdentity : outTransform
            current.alpha = max(0.35, 1 - progress * 0.55)

            let inAngle = dir * (.pi / 2) * (1 - progress)
            var inTransform = CATransform3DTranslate(perspective, dir * width * (1 - progress), 0, 0)
            inTransform = CATransform3DTranslate(inTransform, -dir * halfWidth, 0, 0)
            inTransform = CATransform3DRotate(inTransform, inAngle, 0, 1, 0)
            inTransform = CATransform3DTranslate(inTransform, dir * halfWidth, 0, 0)
            incoming?.layer.transform = progress == 1 ? CATransform3DIdentity : inTransform
            incoming?.alpha = min(1, 0.45 + progress * 0.55)
        default: break
        }
    }

    private func attachMask(_ mask: UIView, to page: UIView) {
        guard maskedPage !== page || page.mask !== mask else { return }
        removeMask()
        page.mask = mask
        maskedPage = page
    }

    private func removeMask() {
        maskedPage?.mask = nil
        maskedPage = nil
    }
}
