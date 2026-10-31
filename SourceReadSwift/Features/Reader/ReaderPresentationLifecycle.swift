import SwiftUI

private struct ReaderTemporaryCoverKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var readerTemporaryCoverPresented: Bool {
        get { self[ReaderTemporaryCoverKey.self] }
        set { self[ReaderTemporaryCoverKey.self] = newValue }
    }
}

/// A full-screen TOC or source picker covers a reader without ending its session.
/// SwiftUI can deliver the presenter's disappear/appear pair for that cover.
/// Treating it as navigation away cancelled jumps, saved entire local books,
/// then restored the original chapter/paragraph on dismissal.
struct ReaderPresentationLifecycle {
    private var coveredByChapterList = false

    mutating func beginAppearance() -> Bool {
        if coveredByChapterList {
            coveredByChapterList = false
            return false
        }
        return true
    }

    mutating func endAppearance(chapterListPresented: Bool) -> Bool {
        coveredByChapterList = chapterListPresented
        return !chapterListPresented
    }
}
