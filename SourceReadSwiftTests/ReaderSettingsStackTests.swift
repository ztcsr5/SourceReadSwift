import SwiftUI
import XCTest
@testable import SourceReadSwift

final class ReaderSettingsStackTests: XCTestCase {
    @MainActor func testSettingsPagesDoNotPropagateOversizedValuesIntoThePanel() {
        let chapter = BookChapter(title: "第一章", url: "local://stack-regression/0",
            bookUrl: "local://stack-regression", index: 0)
        let reader = ReaderView(bookID: "stack-regression",
            content: ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"]),
            chapterIndex: 0, totalChapters: 1)
        // Reserve at least half of the reported 1008 KB device stack even
        // with 32 nested copies; this is a value budget, not an FPS assertion.
        for (page, bytes) in reader.settingsViewValueSizes() {
            print("READER_SETTINGS_VALUE_BYTES \(page)=\(bytes)")
            XCTAssertLessThanOrEqual(bytes, 16 * 1024,
                "\(page) must have a bounded view boundary before joining the settings panel")
        }
    }
}
