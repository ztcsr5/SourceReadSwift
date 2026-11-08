import Foundation

/// Translate a mounted document's flat offset through a newer, not yet mounted chapter window.
enum ReaderWebPositionMapper {
    static func remap(_ flat: Int, from mounted: [WebReaderSection], to current: [WebReaderSection]) -> Int? {
        guard flat >= 0 else { return nil }
        let oldStarts = WebReaderFlatIndexPolicy.starts(forParagraphCounts: mounted.map { $0.paragraphs.count })
        guard let oldIndex = mounted.indices.last(where: { oldStarts[$0] <= flat }),
              flat < oldStarts[oldIndex] + mounted[oldIndex].paragraphs.count,
              let newIndex = current.firstIndex(where: { $0.chapterIndex == mounted[oldIndex].chapterIndex }),
              !current[newIndex].paragraphs.isEmpty else { return nil }
        let starts = WebReaderFlatIndexPolicy.starts(forParagraphCounts: current.map { $0.paragraphs.count })
        return starts[newIndex] + min(flat - oldStarts[oldIndex], current[newIndex].paragraphs.count - 1)
    }
}
