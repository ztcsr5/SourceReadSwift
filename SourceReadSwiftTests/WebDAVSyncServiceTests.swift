import XCTest
@testable import SourceReadSwift

final class WebDAVSyncServiceTests: XCTestCase {

    func testWebDAVConfigDefaultsAndValidation() {
        var config = WebDAVConfig()
        XCTAssertEqual(config.serverURL, "https://dav.jianguoyun.com/dav/")
        XCTAssertEqual(config.remoteDirectory, "SourceReadSwift")
        XCTAssertFalse(config.isConfigured)

        config.username = "reader@example.com"
        config.password = "app-secret-token"
        XCTAssertTrue(config.isConfigured)
    }

    func testURLConstructionAndPercentEncoding() {
        let service = WebDAVSyncService.shared
        let config = WebDAVConfig(
            serverURL: "https://dav.jianguoyun.com/dav",
            username: "user",
            password: "pwd",
            remoteDirectory: "/SourceRead/"
        )

        let dirURL = service.buildDirectoryURL(config: config)
        XCTAssertEqual(dirURL?.absoluteString, "https://dav.jianguoyun.com/dav/SourceRead/")

        let fileURL = service.buildFileURL(config: config, filename: "SourceRead_Backup_2026 09 29.json")
        XCTAssertEqual(fileURL?.absoluteString, "https://dav.jianguoyun.com/dav/SourceRead/SourceRead_Backup_2026%2009%2029.json")
    }

    func testBasicAuthHeaderGeneration() {
        let service = WebDAVSyncService.shared
        let config = WebDAVConfig(
            serverURL: "https://example.com/dav/",
            username: "aladdin",
            password: "open sesame"
        )
        let header = service.authHeader(config: config)
        // "aladdin:open sesame" in base64 is "YWxhZGRpbjpvcGVuIHNlc2FtZQ=="
        XCTAssertEqual(header, "Basic YWxhZGRpbjpvcGVuIHNlc2FtZQ==")
    }

    func testBackupPathsCannotEscapeTheirDirectoryOrChangeURLComponents() throws {
        let service = WebDAVSyncService()
        let config = WebDAVConfig(serverURL: "https://example.com/dav/", remoteDirectory: "纸间/backup")
        let file = try XCTUnwrap(service.buildFileURL(config: config, filename: "book?#%.json"))
        XCTAssertNil(file.query)
        XCTAssertNil(file.fragment)
        XCTAssertEqual(file.lastPathComponent, "book?#%.json")
        for filename in ["../other.json", "folder/other.json", "", "..", "a\u{0000}.json"] {
            XCTAssertNil(service.buildFileURL(config: config, filename: filename))
        }
        XCTAssertNil(service.buildDirectoryURL(config: .init(serverURL: "file:///tmp")))
        XCTAssertNil(service.buildDirectoryURL(config: .init(serverURL: "https://example.com/dav?override=true")))
        XCTAssertNil(service.buildDirectoryURL(config: .init(serverURL: "https://example.com/dav", remoteDirectory: "../outside")))
    }

    func testMalformedRemoteListingDoesNotReturnPartialSuccess() {
        let parser = WebDAVXMLParser(data: Data("<multistatus><response><href>/a.json</href></response>".utf8))
        XCTAssertThrowsError(try parser.parseValidated())
    }

    func testWebDAVXMLParserWithStandardPropfindResponse() {
        let sampleXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/dav/SourceReadSwift/</D:href>
            <D:propstat>
              <D:prop>
                <D:resourcetype><D:collection/></D:resourcetype>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
          <D:response>
            <D:href>/dav/SourceReadSwift/SourceRead_Backup_20260929_120000.json</D:href>
            <D:propstat>
              <D:prop>
                <D:getcontentlength>54321</D:getcontentlength>
                <D:getlastmodified>Tue, 29 Sep 2026 12:00:00 GMT</D:getlastmodified>
                <D:resourcetype/>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
          <D:response>
            <D:href>/dav/SourceReadSwift/readme.txt</D:href>
            <D:propstat>
              <D:prop>
                <D:getcontentlength>120</D:getcontentlength>
                <D:resourcetype/>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """

        let data = sampleXML.data(using: .utf8)!
        let parser = WebDAVXMLParser(data: data)
        let items = parser.parse()

        XCTAssertEqual(items.count, 3)

        let directory = items.first { $0.isDirectory }
        XCTAssertNotNil(directory)
        XCTAssertEqual(directory?.filename, "SourceReadSwift")

        let backups = items.filter { !$0.isDirectory && $0.filename.hasSuffix(".json") }
        XCTAssertEqual(backups.count, 1)

        let backup = backups.first!
        XCTAssertEqual(backup.filename, "SourceRead_Backup_20260929_120000.json")
        XCTAssertEqual(backup.size, 54321)
        XCTAssertNotNil(backup.lastModified)
        XCTAssertEqual(backup.formattedSize, "53.0 KB")
    }

    func testEInkReaderBackgroundPalette() {
        let eink = ReaderBackground.eink
        XCTAssertEqual(eink.title, "水墨屏")
        XCTAssertEqual(eink.dayBackgroundHex, 0xFFFFFF)
        XCTAssertEqual(eink.dayTextHex, 0x000000)
        XCTAssertEqual(eink.nightBackgroundHex, 0x000000)
        XCTAssertEqual(eink.nightTextHex, 0xFFFFFF)
        XCTAssertTrue(eink.darkStatusIcon(isNight: false))
        XCTAssertFalse(eink.darkStatusIcon(isNight: true))
    }

    @MainActor
    func testAppStateBackupSnapshotAndRestore() throws {
        let appState = AppState()
        let snapshot = appState.makeAppDataBackupSnapshot()

        XCTAssertEqual(snapshot.schemaVersion, 3)
        XCTAssertFalse(snapshot.bookshelf.books.isEmpty, "Onboarding book should be seeded")

        XCTAssertNoThrow(try appState.restoreAppDataBackup(snapshot))
    }

    func testWebDAVSyncDecisionDetectsOnlyNewerRemoteBackups() {
        let older = WebDAVRemoteItem(
            href: "/dav/older.json",
            filename: "SourceRead_Backup_older.json",
            lastModified: Date(timeIntervalSince1970: 1_000),
            size: 100,
            isDirectory: false
        )
        let sameName = WebDAVRemoteItem(
            href: "/dav/self.json",
            filename: "SourceRead_Backup_self.json",
            lastModified: Date(timeIntervalSince1970: 5_000),
            size: 100,
            isDirectory: false
        )
        let newer = WebDAVRemoteItem(
            href: "/dav/newer.json",
            filename: "SourceRead_Backup_newer.json",
            lastModified: Date(timeIntervalSince1970: 2_000),
            size: 100,
            isDirectory: false
        )
        let folder = WebDAVRemoteItem(
            href: "/dav/dir/",
            filename: "dir",
            lastModified: Date(timeIntervalSince1970: 9_999),
            size: 0,
            isDirectory: true
        )

        XCTAssertNil(WebDAVSyncDecision.newerRemoteBackup(
            items: [older, folder],
            lastLocalSyncTimestamp: 1_000,
            lastUploadedFilename: nil,
            clockToleranceSeconds: 15
        ))

        XCTAssertNil(WebDAVSyncDecision.newerRemoteBackup(
            items: [sameName],
            lastLocalSyncTimestamp: 1_000,
            lastUploadedFilename: "SourceRead_Backup_self.json",
            clockToleranceSeconds: 15
        ))

        let matched = WebDAVSyncDecision.newerRemoteBackup(
            items: [older, newer, folder],
            lastLocalSyncTimestamp: 1_500,
            lastUploadedFilename: "SourceRead_Backup_older.json",
            clockToleranceSeconds: 15
        )
        XCTAssertEqual(matched?.filename, "SourceRead_Backup_newer.json")
    }
}
