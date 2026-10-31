/// A full-screen TOC temporarily covers a reader; it does not end its session.
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
