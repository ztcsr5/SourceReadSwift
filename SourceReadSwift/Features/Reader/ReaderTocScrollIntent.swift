import Foundation

enum ReaderTocScrollIntent {
    case currentChapter, firstRow

    func target(in chapters: [BookChapter], preferred: Int, fallback: Int) -> String? {
        guard self == .currentChapter else { return chapters.first?.id }
        return (chapters.first { $0.index == preferred }
            ?? chapters.first { $0.index == fallback }
            ?? chapters.first)?.id
    }
}
