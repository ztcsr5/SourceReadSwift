import SwiftUI
import UIKit

/// Visual transition used by the shared three-slot paging surface.
enum CoverPageTurnStyle {
    /// Pages slide sideways like a card stack ("cover").
    case cover
    /// The turning page rotates around its left edge with perspective ("curl").
    case flip
}

/// Cover mode ("覆盖") page surface driven by a paging `UIScrollView`.
///
/// The SwiftUI version displaced three page views with a `@State` translation
/// inside a `GeometryReader`. Every drag frame re-evaluated the reader body,
/// rebuilt `ReaderPageIdentity` for up to three pages and re-diffed a
/// full-screen `ZStack`, which capped the drag on ProMotion hardware and made
/// the mode visibly stutter.
///
/// This surface keeps the same page identity contract but owns the
/// displacement: the pan is driven by UIKit/Core Animation, and SwiftUI only
/// supplies the three page roots when the page model or typography changes.
/// A drag frame therefore never touches a SwiftUI body.
struct CoverPageReaderView: UIViewControllerRepresentable {
    /// Stable key of the page currently in the middle slot.
    var pageIdentity: String
    /// Typography / highlight revision; changes replace the page roots without
    /// resetting the scroll position.
    var contentRevision: String
    /// Stable identity of each slot. A page turn shifts the same page from
    /// one slot to the next, so the host can be moved instead of rebuilt.
    var previousIdentity: String = ""
    var currentIdentity: String = ""
    var nextIdentity: String = ""
    var hasPrevious: Bool
    var hasNext: Bool
    var previous: AnyView?
    var current: AnyView
    var next: AnyView?
    /// -1 = the user pulled the previous page in, +1 = the next page.
    var onCommit: (Int) -> Void
    var onInteractionChange: (Bool) -> Void
    /// Reports the real page container geometry. `.pageTurn` shares this
    /// surface, and its pages live in hosting controllers, so pagination
    /// must measure them instead of the root viewport.
    var onPageContainerLayout: ((CGSize, CGFloat) -> Void)?
    /// `.cover` slides; `.flip` rotates the outgoing page in 3D.
    var turnStyle: CoverPageTurnStyle = .cover

    func makeUIViewController(context: Context) -> CoverPageHostController {
        let controller = CoverPageHostController()
        controller.apply(
            pageIdentity: pageIdentity,
            contentRevision: contentRevision,
            previousIdentity: previousIdentity,
            currentIdentity: currentIdentity,
            nextIdentity: nextIdentity,
            hasPrevious: hasPrevious,
            hasNext: hasNext,
            previous: previous,
            current: current,
            next: next,
            onCommit: onCommit,
            onInteractionChange: onInteractionChange,
            onPageContainerLayout: onPageContainerLayout,
            turnStyle: turnStyle
        )
        return controller
    }

    func updateUIViewController(_ controller: CoverPageHostController, context: Context) {
        controller.apply(
            pageIdentity: pageIdentity,
            contentRevision: contentRevision,
            previousIdentity: previousIdentity,
            currentIdentity: currentIdentity,
            nextIdentity: nextIdentity,
            hasPrevious: hasPrevious,
            hasNext: hasNext,
            previous: previous,
            current: current,
            next: next,
            onCommit: onCommit,
            onInteractionChange: onInteractionChange,
            onPageContainerLayout: onPageContainerLayout,
            turnStyle: turnStyle
        )
    }
}

/// Three-slot paging container: previous / current / next.
///
/// The middle slot is always at `contentOffset.x == width`. Pulling past half
/// a page commits a turn; anything less springs back. The reader then swaps in
/// the new window and this controller recentres without animation, so the page
/// under the user's finger stays the same page.
final class CoverPageHostController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private var hosts: [UIHostingController<AnyView>] = []

    private var pageIdentity = ""
    private var contentRevision = ""
    private var hasPrevious = false
    private var hasNext = false
    private var onCommit: ((Int) -> Void)?
    private var onInteractionChange: ((Bool) -> Void)?
    private var turnStyle: CoverPageTurnStyle = .cover
    private var onPageContainerLayout: ((CGSize, CGFloat) -> Void)?
    private var lastReportedLayoutSize: CGSize = .zero
    private var lastReportedLayoutMinY: CGFloat = .greatestFiniteMagnitude

    /// True while a commit or a spring-back animation is in flight. Layout
    /// passes must not recentre the scroll view during that window.
    private var isSettling = false
    private var settleToken = 0
    private var didInstallContent = false
    /// Page key currently hosted by each physical slot.
    private var slotIdentities = ["", "", ""]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.backgroundColor = .clear
        scrollView.isPagingEnabled = true
        scrollView.bounces = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.scrollsToTop = false
        scrollView.delegate = self
        view.addSubview(scrollView)

        for _ in 0..<3 {
            let host = UIHostingController(rootView: AnyView(EmptyView()))
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
            addChild(host)
            scrollView.addSubview(host.view)
            host.didMove(toParent: self)
            hosts.append(host)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The window can be ready at `makeUIViewController` time, before the
        // view has a size. Recentre once layout produces a real width.
        installFramesIfNeeded(force: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installFramesIfNeeded(force: false)
        reportLayoutIfNeeded()
    }

    /// Publish the measured page viewport once per geometry change. The
    /// reader repaginates from this size, so a stale root-viewport value
    /// would clip the last line of every page.
    private func reportLayoutIfNeeded() {
        let size = view.bounds.size
        guard size.width > 1, size.height > 1, let onPageContainerLayout else { return }
        let minY = view.convert(view.bounds, to: nil).minY
        guard abs(size.width - lastReportedLayoutSize.width) > 0.5
                || abs(size.height - lastReportedLayoutSize.height) > 0.5
                || abs(minY - lastReportedLayoutMinY) > 0.5 else { return }
        lastReportedLayoutSize = size
        lastReportedLayoutMinY = minY
        // Touching SwiftUI state during layoutSubviews raises
        // "modifying state during view update"; defer one runloop.
        DispatchQueue.main.async {
            onPageContainerLayout(size, minY)
        }
    }

    func apply(
        pageIdentity: String,
        contentRevision: String,
        previousIdentity: String,
        currentIdentity: String,
        nextIdentity: String,
        hasPrevious: Bool,
        hasNext: Bool,
        previous: AnyView?,
        current: AnyView,
        next: AnyView?,
        onCommit: @escaping (Int) -> Void,
        onInteractionChange: @escaping (Bool) -> Void,
        onPageContainerLayout: ((CGSize, CGFloat) -> Void)?,
        turnStyle: CoverPageTurnStyle = .cover
    ) {
        loadViewIfNeeded()
        self.onCommit = onCommit
        self.onInteractionChange = onInteractionChange
        self.onPageContainerLayout = onPageContainerLayout
        self.turnStyle = turnStyle
        self.hasPrevious = hasPrevious
        self.hasNext = hasNext

        let identityChanged = self.pageIdentity != pageIdentity
        let revisionChanged = self.contentRevision != contentRevision
        self.pageIdentity = pageIdentity
        self.contentRevision = contentRevision

        guard identityChanged || revisionChanged || !didInstallContent else { return }
        didInstallContent = true

        let roots: [AnyView] = [
            previous ?? AnyView(EmptyView()),
            current,
            next ?? AnyView(EmptyView())
        ]
        let identities = [previousIdentity, currentIdentity, nextIdentity]

        if revisionChanged {
            // Typography / highlight changes invalidate every page.
            for (slot, root) in roots.enumerated() where hosts.indices.contains(slot) {
                hosts[slot].rootView = root
            }
            slotIdentities = identities
        } else {
            // A committed turn shifts previous→current and current→next, so
            // most of the three pages keep their identity. Move the host
            // that already renders the page instead of rebuilding its
            // SwiftUI root, which was the source of the settle stutter.
            var desired: [UIHostingController<AnyView>?] = [nil, nil, nil]
            var claimed = [false, false, false]
            for slot in 0..<3 where slotIdentities[slot] == identities[slot] {
                desired[slot] = hosts[slot]
                claimed[slot] = true
            }
            for slot in 0..<3 where desired[slot] == nil {
                if let donor = (0..<3).first(where: { !claimed[$0] && slotIdentities[$0] == identities[slot] }) {
                    desired[slot] = hosts[donor]
                    claimed[donor] = true
                }
            }
            var rebuilt = false
            for slot in 0..<3 where desired[slot] == nil {
                guard let donor = (0..<3).first(where: { !claimed[$0] }) else { continue }
                claimed[donor] = true
                hosts[donor].rootView = roots[slot]
                desired[slot] = hosts[donor]
                rebuilt = true
            }
            if let first = desired[0], let second = desired[1], let third = desired[2] {
                hosts = [first, second, third]
            } else if rebuilt {
                for (slot, root) in roots.enumerated() where hosts.indices.contains(slot) {
                    hosts[slot].rootView = root
                }
            }
            slotIdentities = identities
        }

        if identityChanged {
            // A committed turn (or an external jump) replaced the window.
            // Recentre on the new current page without animating.
            isSettling = false
            settleToken += 1
            // Rotated hosts may carry the old slot-1 flip transform.
            for host in hosts { host.view.layer.transform = CATransform3DIdentity }
            installFramesIfNeeded(force: true)
        }
    }

    private func installFramesIfNeeded(force: Bool) {
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return }

        let width = size.width
        scrollView.frame = view.bounds
        scrollView.contentSize = CGSize(width: width * 3, height: size.height)

        for (slot, host) in hosts.enumerated() {
            let originX = CGFloat(slot) * width
            // A flip page pivots on its left edge; a cover page pivots on its
            // centre. Setting bounds/position keeps the anchor point stable
            // across relayouts.
            if turnStyle == .flip && slot == 1 {
                host.view.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
                host.view.layer.position = CGPoint(x: originX, y: size.height / 2)
            } else {
                host.view.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                host.view.layer.position = CGPoint(x: originX + width / 2, y: size.height / 2)
            }
            host.view.bounds = CGRect(x: 0, y: 0, width: width, height: size.height)
        }

        guard force || (!scrollView.isDragging && !scrollView.isDecelerating && !isSettling) else { return }
        let centred = CGPoint(x: width, y: 0)
        if scrollView.contentOffset != centred {
            scrollView.setContentOffset(centred, animated: false)
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard turnStyle == .flip else { return }
        let width = max(scrollView.bounds.width, 1)
        let shift = scrollView.contentOffset.x - width
        let progress = min(max(shift / width, -1), 1)
        let angle = ReaderFlipTransitionPolicy.rotationAngle(progress: abs(progress))
        var transform = ReaderFlipTransitionPolicy.perspectiveTransform()
        transform = CATransform3DRotate(transform, progress >= 0 ? angle : -angle, 0, 1, 0)
        hosts[1].view.layer.transform = transform
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onInteractionChange?(true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isSettling = false
        installFramesIfNeeded(force: true)
    }

    private func settle() {
        onInteractionChange?(false)
        guard !isSettling else { return }
        let width = max(scrollView.bounds.width, 1)
        let offset = scrollView.contentOffset.x

        switch ReaderCoverSettlePolicy.outcome(
            contentOffsetX: offset,
            pageWidth: width,
            hasPrevious: hasPrevious,
            hasNext: hasNext
        ) {
        case .previous:
            commit(-1, width: width)
        case .next:
            commit(1, width: width)
        case .springBack:
            springBack(width: width)
        }
    }

    private func commit(_ direction: Int, width: CGFloat) {
        isSettling = true
        settleToken += 1
        let token = settleToken
        onCommit?(direction)
        // The reader normally swaps the window synchronously, which recentres
        // through `apply`. If the neighbour is still loading, recover the
        // middle slot instead of leaving the scroll view parked on an edge.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.settleToken == token, self.isSettling else { return }
            self.isSettling = false
            self.springBack(width: self.scrollView.bounds.width > 1 ? self.scrollView.bounds.width : width)
        }
    }

    private func springBack(width: CGFloat) {
        isSettling = true
        settleToken += 1
        scrollView.setContentOffset(CGPoint(x: width, y: 0), animated: true)
    }
}
