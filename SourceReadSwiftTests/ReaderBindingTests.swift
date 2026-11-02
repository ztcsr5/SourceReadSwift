import SwiftUI
import XCTest
@testable import SourceReadSwift

final class ReaderBindingTests: XCTestCase {
    func testAppearanceSnapshotIsCompleteButCannotContainProgressOrCredentials() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("must-not-export", forKey: "reader.bookID")
        defaults.set(999, forKey: "reader.currentParagraphIndex")
        defaults.set("must-not-export", forKey: "provider.apiKey")
        defaults.set("mountains", forKey: "reader.chapterDecoration")
        defaults.set(0.9, forKey: "reader.menuPaperOpacity")
        let preferences = try ReaderBindingPreferences.capture(defaults)
        XCTAssertEqual(Set(preferences.values.keys), Set(ReaderBindingPreferences.defaults.keys))
        XCTAssertNil(preferences.values["reader.currentParagraphIndex"])
        XCTAssertNil(preferences.values["reader.bookID"])
        XCTAssertNil(preferences.values["provider.apiKey"])
        let encoded = try JSONEncoder().encode(preferences)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("must-not-export"))
        let restored = try JSONDecoder().decode(ReaderBindingPreferences.self, from: encoded)
        defaults.set("none", forKey: "reader.chapterDecoration")
        try restored.apply(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "reader.chapterDecoration"), "mountains")
        XCTAssertEqual(defaults.double(forKey: "reader.menuPaperOpacity"), 0.9)
        XCTAssertEqual(defaults.integer(forKey: "reader.currentParagraphIndex"), 999)
    }
    func testInvalidSnapshotCannotPartiallyChangePreferences() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(22, forKey: "reader.fontSize")
        var values = ReaderBindingPreferences.defaults
        values["reader.fontSize"] = .number(28)
        values["reader.headerOpacity"] = .number(.infinity)
        XCTAssertThrowsError(try ReaderBindingPreferences(values: values).apply(to: defaults))
        XCTAssertEqual(defaults.double(forKey: "reader.fontSize"), 22)
        values = ReaderBindingPreferences.defaults; values["provider.apiKey"] = .text("not-permitted")
        XCTAssertThrowsError(try ReaderBindingPreferences(values: values).validate())
        values = ReaderBindingPreferences.defaults; values["reader.chapterDecoration"] = .text("unknown")
        XCTAssertThrowsError(try ReaderBindingPreferences(values: values).validate())
    }
    func testAtomicRepositorySurvivesRelaunchAndStoresWallpaperWithoutRecompression() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ReaderBindingRepository(root: root)
        var values = ReaderBindingPreferences.defaults; values["reader.background"] = .text("custom")
        var adjustment = ReaderWallpaperAdjustment(); adjustment.zoom = 1.7; adjustment.horizontalOffset = -0.4
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 40)).image { renderer in
            UIColor.systemTeal.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 24, height: 40))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let record = ReaderBindingRecord(version: 1, id: UUID(), title: "山岚夜读", createdAt: Date(),
            preferences: ReaderBindingPreferences(values: values), hasWallpaper: true)
        try await repository.save(record, wallpaper: ReaderBindingWallpaper(jpeg: jpeg, adjustment: adjustment))
        let relaunched = ReaderBindingRepository(root: root)
        let loaded = try await relaunched.records(); XCTAssertEqual(loaded, [record])
        let wallpaper = try await relaunched.wallpaper(for: record.id)
        XCTAssertEqual(wallpaper.jpeg, jpeg); XCTAssertEqual(wallpaper.adjustment, adjustment)
        do { try await repository.save(record, wallpaper: wallpaper); XCTFail("Existing UUID must never be overwritten") } catch {}
        let unchanged = try await relaunched.wallpaper(for: record.id)
        XCTAssertEqual(unchanged.jpeg, jpeg)
        try await relaunched.delete(record.id)
        let remaining = try await relaunched.records()
        XCTAssertTrue(remaining.isEmpty)
    }
    @MainActor func testMissingCustomFontRejectsTheWholeApplyBeforeChangingSettings() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(19, forKey: "reader.fontSize")
        var values = ReaderBindingPreferences.defaults
        values["reader.fontSize"] = .number(28)
        values["reader.fontFamily"] = .text(ReaderFontFamily.custom.rawValue)
        values["reader.customFontPostScriptName"] = .text("not-installed-unique-font")
        let record = ReaderBindingRecord(version: 1, id: UUID(), title: "未安装字体", createdAt: Date(),
            preferences: .init(values: values), hasWallpaper: false)
        let store = ReaderBindingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        do { try await store.apply(record, defaults: defaults); XCTFail("Missing font must not silently use a fallback") }
        catch { XCTAssertEqual((error as NSError).code, 4) }
        XCTAssertEqual(defaults.double(forKey: "reader.fontSize"), 19)
    }
    func testDecoratedHeadingPaginationConservesTitleAndAllSourceCharacterOffsets() {
        let title = String(repeating: "第九章 山中来信与长标题👩🏽‍💻 ", count: 12)
        let paragraphs = [String(repeating: "正文 Mixed 中文，字符锚点不能改变。", count: 90), "末段"]
        for decoration in ReaderChapterDecoration.allCases {
            let typography = ReaderPageTypography(font: .systemFont(ofSize: 20), titleFont: .boldSystemFont(ofSize: 26),
                lineSpacing: 8, letterSpacing: 0, paragraphSpacing: 16, firstLineIndent: 40, titleSpacing: 12,
                contentWidth: 278, contentHeight: 330, chapterDecoration: decoration, chapterAlignment: .center)
            let context = ReaderChapterPaginationContext(typography: typography, titleTypography: typography,
                chromeLayout: .inline, imageStyle: .standard, viewportHeight: 568, pagePadding: 21, footerHeight: 60, traditionalChinese: false)
            let pages = ReaderTextPagePaginator.paginate(chapterIndex: 0, title: title, paragraphs: paragraphs, context: context)
            XCTAssertEqual(pages.compactMap(\.inlineTitleText).joined(), title)
            for (index, paragraph) in paragraphs.enumerated() {
                let entries = pages.flatMap(\.paragraphs).filter { $0.index == index }
                XCTAssertEqual(entries.map(\.text).joined(), paragraph)
                var offset = 0
                for entry in entries { XCTAssertEqual(entry.sourceUTF16Offset, offset); offset += entry.text.utf16.count }
            }
            XCTAssertEqual(pages.first?.pageOrdinal, 0)
            XCTAssertFalse(pages.contains { !$0.includesTitle && $0.paragraphs.isEmpty })
        }
    }
}
