import Foundation

/// Presentation helpers shared by the compact chapter list and the full TOC
/// sheet.  Kept free of SwiftUI so the volume/update-time rules can be tested.
enum ChapterListPresenter {
    /// Returns the volume heading that must be rendered before `index`, or nil
    /// when the chapter continues the previous volume or carries no volume name.
    static func volumeHeader(at index: Int, in chapters: [BookChapter]) -> String? {
        guard chapters.indices.contains(index) else { return nil }
        guard let volume = normalizedVolume(chapters[index].volumeName) else { return nil }
        if index == 0 { return volume }
        return normalizedVolume(chapters[index - 1].volumeName) == volume ? nil : volume
    }

    /// Source-formatted update timestamp, trimmed and dropped when empty.
    static func updateLabel(_ chapter: BookChapter) -> String? {
        guard let value = chapter.updateTime?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func normalizedVolume(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
