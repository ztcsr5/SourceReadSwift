import SwiftUI
import UIKit

/// Keep system menu presentation and accessibility in UIKit. The page's tap
/// recognizer is attached to the reading surface, not this chrome control.
struct ReaderNativeMenuButton: UIViewRepresentable {
    let menu: UIMenu
    let foregroundColor: UIColor
    let backgroundColor: UIColor

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = "更多操作"
        button.accessibilityIdentifier = "reader.more"
        button.showsMenuAsPrimaryAction = true
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        button.layer.cornerRadius = 22
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.menu = menu
        button.tintColor = foregroundColor
        button.backgroundColor = backgroundColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }
}
