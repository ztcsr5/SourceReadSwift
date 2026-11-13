import SwiftUI

/// One navigation request keeps its loading destination stable until native return completes.
struct ReaderDestinationRequest: Identifiable {
    let id = UUID()
    let book: BookshelfBook
    var sourceID: String?
    /// Set when the caller asked for one concrete chapter. A parked reader can
    /// only be shown again when both requests resume the same position.
    var requestedChapterIndex: Int?
    var onReturn: () -> Void = {}
    let makeContent: (@escaping () -> Void) -> AnyView

    static func shelf(_ book: BookshelfBook, bookmark: ReaderBookmark? = nil,
                      chapterIndex: Int? = nil, sourceID: String? = nil) -> Self {
        Self(book: book, sourceID: sourceID, requestedChapterIndex: chapterIndex) { close in
            AnyView(BookshelfReaderGatewayView(book: book, initialBookmark: bookmark,
                initialChapterIndex: chapterIndex, onRequestExit: close))
        }
    }
}
