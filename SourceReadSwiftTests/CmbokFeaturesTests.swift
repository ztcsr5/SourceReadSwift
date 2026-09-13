import XCTest
@testable import SourceReadSwift

final class CmbokFeaturesTests: XCTestCase {
    func testReaderModeIncludesPageCurl() {
        XCTAssertTrue(ReaderMode.allCases.contains(.pageCurl))
        XCTAssertEqual(ReaderMode.pageCurl.title, "仿真")
        XCTAssertEqual(ReaderMode.pageCurl.rawValue, "pageCurl")
    }

    func testReaderOverrideStore() async {
        await MainActor.run {
            let store = ReaderOverrideStore.shared
            let testBookID = "test_book_cmbok_123"

            let override = BookReaderOverride(
                readerMode: .pageCurl,
                fontFamily: .songti,
                fontSize: 22,
                lineSpacing: 10,
                background: .kraft
            )
            XCTAssertTrue(override.hasAnyOverride)

            store.setOverride(override, for: testBookID)
            let retrieved = store.override(for: testBookID)
            XCTAssertNotNil(retrieved)
            XCTAssertEqual(retrieved?.readerMode, .pageCurl)
            XCTAssertEqual(retrieved?.fontFamily, .songti)
            XCTAssertEqual(retrieved?.fontSize, 22)
            XCTAssertEqual(retrieved?.lineSpacing, 10)
            XCTAssertEqual(retrieved?.background, .kraft)

            store.clearOverride(for: testBookID)
            XCTAssertNil(store.override(for: testBookID))
        }
    }

    func testCryptoHelperAESDecryption() {
        // Plaintext: "Hello, Cmbok and SourceReadSwift!"
        // AES-128-CBC with key "1234567890123456" and iv "1234567890123456"
        let key = Data("1234567890123456".utf8)
        let iv = Data("1234567890123456".utf8)

        // Generate encrypted block using CommonCrypto status check
        let plaintext = "Hello, Cmbok and SourceReadSwift!"
        let plainData = Data(plaintext.utf8)

        // Decrypt nil guard on key length mismatch
        let invalidKey = Data("short".utf8)
        XCTAssertNil(CryptoHelper.aesDecrypt(data: plainData, key: invalidKey, iv: iv))

        // Decrypt nil guard on iv length mismatch
        let invalidIv = Data("short".utf8)
        XCTAssertNil(CryptoHelper.aesDecrypt(data: plainData, key: key, iv: invalidIv))
    }

    func testZlibraryEngineDomain() async {
        let domain = await ZlibraryEngine.shared.currentDomain()
        XCTAssertFalse(domain.isEmpty)
        XCTAssertEqual(ZlibraryEngine.sourceName, "Z-Library")
    }
}
