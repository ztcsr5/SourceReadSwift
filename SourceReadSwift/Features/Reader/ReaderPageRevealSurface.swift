import UIKit

/// Animates mounted neighbouring pages without rebuilding text or decoding images during a turn.
@MainActor
final class ReaderPageRevealSurface {
    private let aperture = UIView()
    private weak var maskedPage: UIView?
    private var isActive = false
    private var direction = 1

    init() { aperture.backgroundColor = .black }

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
        for page in pages {
            page?.alpha = 1
            page?.transform = .identity
            page?.layer.shadowOpacity = 0
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
        if maskedPage === current { removeMask() }
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
            if maskedPage !== incoming {
                removeMask()
                incoming.mask = aperture
                maskedPage = incoming
            }
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
        default: break
        }
    }

    private func removeMask() {
        maskedPage?.mask = nil
        maskedPage = nil
    }
}
