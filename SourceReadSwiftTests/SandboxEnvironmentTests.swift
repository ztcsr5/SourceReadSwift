import XCTest
@testable import SourceReadSwift

final class SandboxEnvironmentTests: XCTestCase {
    func testSandboxEnvironmentDefaults() {
        XCTAssertGreaterThan(SandboxEnvironment.recommendedBatchConcurrency, 0)
    }

    func testAppStorageDirectoryResolution() {
        let storageURL = AppStorageDirectory.appStorageURL(fileName: "test.json")
        XCTAssertTrue(storageURL.path.contains("test.json"))
    }

    func testAppStorageDirectorySafeWrite() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetFile = tempDir.appendingPathComponent("test_data.json")
        let testString = "Hello LiveContainer Sandbox"
        let data = try XCTUnwrap(testString.data(using: .utf8))

        try AppStorageDirectory.safeWrite(data, to: targetFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path))

        let readData = try Data(contentsOf: targetFile)
        XCTAssertEqual(String(data: readData, encoding: .utf8), testString)
    }
}
