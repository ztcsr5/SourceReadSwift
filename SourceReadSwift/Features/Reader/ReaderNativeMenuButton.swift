import SwiftUI
import UIKit

/// Keep system menu presentation and accessibility in UIKit. The page's tap
/// recognizer is attached to the reading surface, not this chrome control.
struct ReaderNativeMenuButton: UIViewRepresentable {
    let menuIdentity: String
    let makeMenu: () -> UIMenu
    let foregroundColor: UIColor
    let backgroundColor: UIColor
    var systemImage = "ellipsis"
    var accessibilityIdentifier = "reader.more"
    var accessibilityLabel = "更多操作"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        button.showsMenuAsPrimaryAction = true
        button.layer.cornerRadius = 22
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.apply(to: button, identity: menuIdentity, makeMenu: makeMenu)
        button.tintColor = foregroundColor
        button.backgroundColor = backgroundColor
        button.setImage(UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }

    final class Coordinator {
        private var identity: String?
        private(set) var buildCount = 0

        func apply(to button: UIButton, identity: String, makeMenu: () -> UIMenu) {
            guard self.identity != identity else { return }
            self.identity = identity
            buildCount += 1
            button.menu = makeMenu()
        }
    }
}
