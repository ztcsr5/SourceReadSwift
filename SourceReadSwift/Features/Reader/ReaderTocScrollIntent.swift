import Foundation

enum ReaderTocScrollIntent {
    case currentChapter, firstRow

    func target(in chapters: [BookChapter], preferred: Int, fallback: Int) -> String? {
        row(in: chapters, preferred: preferred, fallback: fallback).map { chapters[$0].id }
    }

    func row(in chapters: [BookChapter], preferred: Int, fallback: Int) -> Int? {
        guard !chapters.isEmpty else { return nil }
        guard self == .currentChapter else { return 0 }
        return chapters.firstIndex { $0.index == preferred }
            ?? chapters.firstIndex { $0.index == fallback }
            ?? 0
    }
}
