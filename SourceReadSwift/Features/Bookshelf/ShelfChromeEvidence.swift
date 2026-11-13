import SwiftUI
import UIKit

/// Live navigation-chrome evidence for the shelf root.
///
/// The report "主页 appears late and the content shifts down" can come from
/// three different places: the bar staying hidden, the large-title preference
/// flipping after the pop, or the whole SwiftUI body being rebuilt. Reading the
/// real `UINavigationBar` at query time separates them; no timer and no
/// snapshot of a SwiftUI-computed guess. Release builds mount nothing.
struct ShelfChromeEvidence: View {
    var body: some View {
        #if DEBUG
        // No opacity trick: XCUITest drops zero-alpha elements from the tree, and the
        // clear background already makes this invisible. 1x1 keeps layout untouched.
        ShelfChromeProbe().frame(width: 1, height: 1).allowsHitTesting(false)
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG
private struct ShelfChromeProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> EvidenceView { EvidenceView() }
    func updateUIView(_ view: EvidenceView, context: Context) {}

    final class EvidenceView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = true
            accessibilityIdentifier = "bookshelf.chromeEvidence"
            accessibilityLabel = "书架导航栏状态"
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Created programmatically") }

        /// One line, machine-readable, and honest about which stack it read.
        /// The shelf lives inside a SwiftUI stack that may itself be hosted by
        /// the outer reader stack, whose bar is deliberately hidden — so a
        /// single "first navigation found" answer can be the wrong bar. Report
        /// every stack reachable from here and pre-compute the only question
        /// the test actually asks: is any visible bar already showing 主页?
        override var accessibilityValue: String? {
            get {
                guard let window else { return "detached" }
                let stacks = Self.navigationControllers(from: self, window: window)
                guard !stacks.isEmpty else { return "noNavigation" }
                var revealsHome = false
                let entries = stacks.enumerated().map { index, navigation -> String in
                    let bar = navigation.navigationBar
                    let frame = bar.convert(bar.bounds, to: window)
                    let item = navigation.topViewController?.navigationItem
                    let title = item?.title ?? "nil"
                    let mode = Self.modeName(item?.largeTitleDisplayMode)
                    let visible = !bar.isHidden && bar.alpha >= 0.99
                    if visible, title == "主页", mode == "always" { revealsHome = true }
                    return "[" + [
                        "i=\(index)",
                        "top=\(navigation.topViewController.map { String(describing: type(of: $0)) } ?? "none")",
                        "depth=\(navigation.viewControllers.count)",
                        "hidden=\(bar.isHidden)",
                        "alpha=\(String(format: "%.2f", bar.alpha))",
                        "y=\(Int(frame.minY))",
                        "h=\(Int(frame.height))",
                        "prefersLarge=\(bar.prefersLargeTitles)",
                        "title=\(title)",
                        "mode=\(mode)",
                        "pop=\(navigation.interactivePopGestureRecognizer?.state.rawValue ?? 0)"
                    ].joined(separator: ",") + "]"
                }
                // Whether the zoom source cover is merely hidden for the transition or
                // actually gone is the difference between "cover stayed in place, pixels
                // suppressed" and "card was rebuilt". Report it alongside the chrome.
                let covers = ReaderZoomSources.shared.visibilityEvidenceForAllIDs()
                return "visibleHome=\(revealsHome);count=\(stacks.count);coverVisible=\(covers);" + entries.joined(separator: "|")
            }
            set {}
        }

        /// Raw integers here would encode an enum order nobody can re-read in a
        /// failure log; print the case name UIKit actually resolved.
        private static func modeName(_ mode: UINavigationItem.LargeTitleDisplayMode?) -> String {
            switch mode {
            case .automatic: return "automatic"
            case .always: return "always"
            case .never: return "never"
            default: return "nil"
            }
        }

        /// Walk out through the responder chain first: that finds the SwiftUI
        /// stack this view is actually inside, without assuming a parent type.
        /// Only if the chain yields nothing fall back to the window tree.
        private static func navigationControllers(from view: UIView, window: UIWindow) -> [UINavigationController] {
            var found: [UINavigationController] = []
            func add(_ navigation: UINavigationController?) {
                guard let navigation, !found.contains(where: { $0 === navigation }) else { return }
                found.append(navigation)
            }
            var responder: UIResponder? = view
            while let current = responder {
                add(current as? UINavigationController)
                add((current as? UIViewController)?.navigationController)
                responder = current.next
            }
            if found.isEmpty {
                var pending = [window.rootViewController].compactMap { $0 }
                while let controller = pending.popLast() {
                    if let navigation = controller as? UINavigationController { add(navigation) }
                    pending.append(contentsOf: controller.children)
                    if let presented = controller.presentedViewController { pending.append(presented) }
                }
            }
            return found
        }
    }
}
#endif