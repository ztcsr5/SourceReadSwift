import SwiftUI

/// App chrome/content density, deliberately independent of reader typography.
/// Safe-area space belongs to the root container, not every child page.
enum AppLayout {
    static let pageMargin: CGFloat = 16
    static let cardInset: CGFloat = 12
    static let sectionGap: CGFloat = 14
    static let rowGap: CGFloat = 8
    static let contentTail: CGFloat = 12
    static let minimumTapTarget: CGFloat = 44
    static let tabVerticalInset: CGFloat = 5
    static let continueCardWidth: CGFloat = 288
}
