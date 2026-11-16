import Foundation

/// An ordinal within a directory entry, stable when another chapter shifts the collection indices.
struct ComicStripPageKey: Hashable {
    let chapterOffset: Int
    let pageIndex: Int
}

struct ComicStripPage {
    let key: ComicStripPageKey
    let request: ComicImageRequest
}

struct ComicStripChapter {
    let offset: Int
    let resources: ComicChapterResources
    let requests: [ComicImageRequest]
}

struct ComicStripSnapshot {
    let revision = UUID()
    let pages: [ComicStripPage]
    let indices: [ComicStripPageKey: Int]

    init(chapters: [ComicStripChapter] = []) {
        pages = chapters.flatMap { chapter in
            chapter.requests.enumerated().map { index, request in
                ComicStripPage(key: .init(chapterOffset: chapter.offset, pageIndex: index), request: request)
            }
        }
        indices = Dictionary(uniqueKeysWithValues: pages.enumerated().map { ($0.element.key, $0.offset) })
    }
}

/// Holds the reading chapter and at most its two immediate neighbours. Faraway prefetch stays in the address cache.
struct ComicStripChapterWindow {
    private(set) var chapters: [ComicStripChapter] = []
    private(set) var snapshot = ComicStripSnapshot()

    var firstOffset: Int? { chapters.first?.offset }
    var lastOffset: Int? { chapters.last?.offset }
    var needsMorePages: Bool { chapters.last?.resources.hasPendingContinuation == true }

    func chapter(at offset: Int) -> ComicStripChapter? { chapters.first { $0.offset == offset } }

    mutating func reset(to chapter: ComicStripChapter) {
        chapters = [chapter]
        rebuildSnapshot()
    }

    /// Stitches only complete, immediate neighbours; a hole must never be passed off as continuous reading.
    @discardableResult
    mutating func stitch(_ chapter: ComicStripChapter, around visibleOffset: Int) -> Bool {
        guard chapter.resources.canReuseFromCache, !chapter.requests.isEmpty,
              abs(chapter.offset - visibleOffset) == 1,
              let firstOffset, let lastOffset else { return false }
        if chapter.offset == firstOffset - 1 {
            chapters.insert(chapter, at: 0)
        } else if chapter.offset == lastOffset + 1, !needsMorePages {
            chapters.append(chapter)
        } else {
            return false
        }
        retain(around: visibleOffset, radius: 1)
        rebuildSnapshot()
        return true
    }

    @discardableResult
    mutating func prune(around visibleOffset: Int, includesNeighbours: Bool = true) -> Bool {
        guard chapter(at: visibleOffset) != nil else { return false }
        let previousCount = chapters.count
        retain(around: visibleOffset, radius: includesNeighbours ? 1 : 0)
        guard chapters.count != previousCount else { return false }
        rebuildSnapshot()
        return true
    }

    private mutating func rebuildSnapshot() { snapshot = ComicStripSnapshot(chapters: chapters) }

    private mutating func retain(around visibleOffset: Int, radius: Int) {
        chapters.removeAll { abs($0.offset - visibleOffset) > radius }
    }
}
