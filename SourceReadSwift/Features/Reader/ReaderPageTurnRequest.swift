import Foundation

/// Tap input is a request, not a cursor write. UIKit commits the cursor only
/// after the same animation transaction used by a swipe has finished.
struct ReaderPageTurnRequest: Equatable {
    let id = UUID()
    let direction: Int
}
