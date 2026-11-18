import UIKit

/// Animates mounted neighbouring pages without rebuilding text or decoding images during a turn.
@MainActor
final class ReaderPageRevealSurface {
    private let aperture = UIView()
    private let splitAperture = UIView()
    private weak var maskedPage: UIView?
    private var isActive = false
    private var direction = 1
    private var configuredCurrent: ObjectIdentifier?
    private var configuredIncoming: ObjectIdentifier?
    private var configuredStyle: CoverPageTurnStyle?

    init() {
        aperture.backgroundColor = .black
        splitAperture.backgroundColor = .black
    }

    func prepare(direction: Int, style: CoverPageTurnStyle, in container: UIView, pages: [UIView?]) {
        self.direction = direction < 0 ? -1 : 1
        UIView.performWithoutAnimation {
            apply(style: style, translation: 0, in: container, pages: pages)
        }
    }

    func reset(pages: [UIView?]) {
        guard isActive else { return }
        isActive = false
        maskedPage?.mask = nil
        maskedPage = nil
        configuredCurrent = nil
        configuredIncoming = nil
        configuredStyle = nil
        for page in pages {
            page?.alpha = 1
            page?.transform = .identity
            page?.layer.transform = CATransform3DIdentity
            page?.layer.shadowOpacity = 0
            if page?.layer.shouldRasterize == true {
                page?.layer.shouldRasterize = false
            }
            page?.isUserInteractionEnabled = true
            page?.accessibilityElementsHidden = false
        }
    }

    func apply(style: CoverPageTurnStyle, translation: CGFloat, in container: UIView, pages: [UIView?]) {
        guard pages.count == 3, let current = pages[1] else { return }
        isActive = true
        let width = max(container.bounds.width, 1)
        let progress = min(abs(translation) / width, 1)
        if translation != 0 { direction = translation > 0 ? -1 : 1 }
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
            // A perspective turn uses the layer transform while the other
            // styles use UIView transforms; clear both before a mode/page
            // handoff so transforms never compound across turns.
            for page in [current, incoming, outgoingNeighbour].compactMap({ $0 }) {
                page.transform = .identity
                page.layer.transform = CATransform3DIdentity
            }
            let scale = max(container.window?.screen.scale ?? UIScreen.main.scale, 2)
            let needsRaster = style == .dissolve || style == .stacked || style == .perspective
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
            if let incoming, container.subviews.last !== incoming { container.bringSubviewToFront(incoming) }
            configuredCurrent = ObjectIdentifier(current)
            configuredIncoming = incomingID
            configuredStyle = style
        }

        switch style {
        case .dissolve:
            removeMask()
            current.transform = .identity
            current.alpha = 1
            incoming?.transform = .identity
            incoming?.alpha = progress
        case .stacked:
            removeMask()
            current.alpha = 1 - progress * 0.35
            current.transform = CGAffineTransform(scaleX: 1 - 0.045 * progress, y: 1 - 0.045 * progress)
            incoming?.alpha = 1
            incoming?.transform = CGAffineTransform(translationX: CGFloat(direction) * width * (1 - progress), y: 0)
        case .ripple:
            current.alpha = 1
            current.transform = .identity
            incoming?.alpha = 1
            incoming?.transform = .identity
            guard let incoming else { removeMask(); return }
            attachMask(aperture, to: incoming)
            let diameter = hypot(container.bounds.width, container.bounds.height) * 2
            if aperture.bounds.width != diameter {
                aperture.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                aperture.layer.cornerRadius = diameter / 2
            }
            aperture.center = CGPoint(x: width * (direction < 0 ? 0.24 : 0.76), y: container.bounds.midY)
            // UIView's transform is interpolated by the same property animator as the page turn.
            // Replacing a CGPath here would jump straight to the final mask on programmatic turns.
            let scale = max(progress, 0.0001)
            aperture.transform = CGAffineTransform(scaleX: scale, y: scale)
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
