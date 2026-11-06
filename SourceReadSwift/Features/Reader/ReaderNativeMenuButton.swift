import SwiftUI
import UIKit

/// Non-publishing guard for taps delivered to prose by UIKit's menu backdrop.
@MainActor final class ReaderMenuPresentation {
    private var activeConfiguration: ObjectIdentifier?
    var isActive: Bool { activeConfiguration != nil }

    func begin(_ configuration: ObjectIdentifier) { activeConfiguration = configuration }

    func end(_ configuration: ObjectIdentifier) {
        if activeConfiguration == configuration { activeConfiguration = nil }
    }
}

/// Present UIKit's accessible menu without rebuilding it on progress updates.
struct ReaderNativeMenuButton: UIViewRepresentable {
    let menuIdentity: String
    let makeMenu: () -> UIMenu
    let foregroundColor: UIColor
    let backgroundColor: UIColor
    var systemImage = "ellipsis"
    var accessibilityIdentifier = "reader.more"
    var accessibilityLabel = "更多操作"
    var presentation: ReaderMenuPresentation? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MenuControl {
        let button = MenuControl(type: .system)
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        button.showsMenuAsPrimaryAction = true
        button.layer.cornerRadius = 22
        return button
    }

    func updateUIView(_ button: MenuControl, context: Context) {
        button.presentation = presentation
        context.coordinator.apply(to: button, identity: menuIdentity, makeMenu: makeMenu)
        button.tintColor = foregroundColor
        button.backgroundColor = backgroundColor
        button.setImage(UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MenuControl, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }

    static func dismantleUIView(_ button: MenuControl, coordinator: Coordinator) {
        button.releasePresentation()
    }

    final class MenuControl: UIButton {
        weak var presentation: ReaderMenuPresentation?
        private var presentedConfiguration: ObjectIdentifier?

        override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
            willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
            super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
            let identity = ObjectIdentifier(configuration)
            presentedConfiguration = identity
            presentation?.begin(identity)
        }

        override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
            super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
            let identity = ObjectIdentifier(configuration)
            let finish = { [weak self] in
                guard let self, self.presentedConfiguration == identity else { return }
                self.releasePresentation()
            }
            // The dismissal touch may also be delivered to the page while
            // UIKit animates the menu away. Keep the gate until that ends.
            if let animator { animator.addCompletion(finish) }
            else { DispatchQueue.main.async(execute: finish) }
        }

        func releasePresentation() {
            guard let presentedConfiguration else { return }
            self.presentedConfiguration = nil
            presentation?.end(presentedConfiguration)
        }
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
