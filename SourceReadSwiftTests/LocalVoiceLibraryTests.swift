import XCTest
@testable import SourceReadSwift

/// 本地音频包的命名解析是 `.file` 朗读通道的唯一契约：
/// 文件名解析错 = 朗读到错段落，所以这里把常见命名都锁成用例。
final class LocalVoiceLibraryTests: XCTestCase {

    func testFailedReplacementPreservesThePreviouslyImportedAudio() throws {
        LocalVoiceLibrary.ensureDirectory()
        let name = UUID().uuidString + ".mp3"
        let destination = LocalVoiceLibrary.directory.appendingPathComponent(name)
        let original = Data("previous-audio".utf8)
        try original.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent(name)

        XCTAssertEqual(LocalVoiceLibrary.importFiles([missing]), 0)
        XCTAssertEqual(try Data(contentsOf: destination), original,
                       "An unavailable replacement must not delete audio that already works")
    }

    func testImportingAnAlreadyStoredFileDoesNotDeleteIt() throws {
        LocalVoiceLibrary.ensureDirectory()
        let destination = LocalVoiceLibrary.directory.appendingPathComponent(UUID().uuidString + ".mp3")
        let original = Data("existing-audio".utf8)
        try original.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }

        XCTAssertEqual(LocalVoiceLibrary.importFiles([destination]), 1)
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }

    func testPlainNumericNames() {
        XCTAssertEqual(LocalVoiceLibrary.paragraphIndex(ofFileName: "0.mp3"), 0)
        XCTAssertEqual(LocalVoiceLibrary.paragraphIndex(ofFileName: "12.m4a"), 12)
        XCTAssertEqual(LocalVoiceLibrary.paragraphIndex(ofFileName: "007.wav"), 7)
    }

    func testPrefixedNames() {
        XCTAssertEqual(LocalVoiceLibrary.paragraphIndex(ofFileName: "p3.mp3"), 3)
        XCTAssertEqual(LocalVoiceLibrary.paragraphIndex(ofFileName: "P03 - 序章.wav"), 3)
        XCTAssertEqual(LocalVoiceLibrary.paragraphIndex(ofFileName: "para11.flac"), 11)
    }

    func testChineseNameWithTrailingText() {
        XCTAssertEqual(LocalVoiceLibrary.paragraphIndex(ofFileName: "第3段.mp3"), 3)
        XCTAssertEqual(LocalVoiceLibrary.paragraphIndex(ofFileName: "5 - 荷塘月色.m4a"), 5)
    }

    func testNamesWithoutIndexAreRejected() {
        XCTAssertNil(LocalVoiceLibrary.paragraphIndex(ofFileName: "cover.jpg"))
        XCTAssertNil(LocalVoiceLibrary.paragraphIndex(ofFileName: "intro.mp3"))
        XCTAssertNil(LocalVoiceLibrary.paragraphIndex(ofFileName: "zzz.wav"))
    }

    func testCaseInsensitivePrefix() {
        XCTAssertEqual(LocalVoiceLibrary.paragraphIndex(ofFileName: "P9.MP3"), 9)
    }

    /// 目录内没有文件时，`fileURL(forParagraph:)` 必须返回 nil，
    /// 由朗读器跳过该段而不是抛错。
    func testMissingFileReturnsNil() {
        LocalVoiceLibrary.clear()
        XCTAssertNil(LocalVoiceLibrary.fileURL(forParagraph: 0))
        XCTAssertTrue(LocalVoiceLibrary.isEmpty)
    }
}
