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

    func testDetectsLiveContainerAcrossEnvironmentPathsClassesAndDyldImages() {
        XCTAssertFalse(SandboxEnvironment.detectLiveContainer(
            environment: [:],
            bundlePath: "/private/var/containers/Bundle/Application/1234/SourceReadSwift.app",
            homeDirectory: "/var/mobile/Containers/Data/Application/5678",
            bundleIdentifier: "com.edc21.SourceReadSwift",
            executablePath: "/private/var/containers/Bundle/Application/1234/SourceReadSwift.app/SourceReadSwift"
        ))

        XCTAssertTrue(SandboxEnvironment.detectLiveContainer(
            environment: ["LC_HOME_PATH": "/var/mobile/Containers/Data/Application/LC"],
            bundlePath: "/var/mobile/App.app",
            homeDirectory: "/var/mobile",
            bundleIdentifier: "com.example.guest",
            executablePath: "/var/mobile/App.app/App"
        ))

        XCTAssertTrue(SandboxEnvironment.detectLiveContainer(
            environment: [:],
            bundlePath: "/var/mobile/Containers/Data/Application/9999/Documents/Applications/SourceReadSwift.app",
            homeDirectory: "/var/mobile/Containers/Data/Application/9999/Documents/Data/Application/1111",
            bundleIdentifier: "com.custom.repackaged",
            executablePath: "/var/mobile/Containers/Data/Application/9999/Documents/Applications/SourceReadSwift.app/SourceReadSwift"
        ))

        XCTAssertTrue(SandboxEnvironment.detectLiveContainer(
            environment: [:],
            bundlePath: "/var/mobile/App.app",
            homeDirectory: "/var/mobile",
            bundleIdentifier: "com.example.guest",
            executablePath: "/var/mobile/App.app/App",
            loadedImageNames: ["/private/var/mobile/Containers/Data/Application/XYZ/Documents/Tweaks/TweakLoader.dylib"]
        ))

        XCTAssertTrue(SandboxEnvironment.detectLiveContainer(
            environment: [:],
            bundlePath: "/var/mobile/App.app",
            homeDirectory: "/var/mobile/Containers/Data/Application/9999/Documents/Data/Application/1111",
            bundleIdentifier: "com.edc21.SourceReadSwift",
            executablePath: "/var/mobile/App.app/App"
        ))

        XCTAssertTrue(SandboxEnvironment.detectLiveContainer(
            environment: [:],
            bundlePath: "/var/mobile/App.app",
            homeDirectory: "/var/mobile",
            bundleIdentifier: "com.example.guest",
            executablePath: "/var/mobile/App.app/App",
            hasLiveContainerClass: true
        ))
    }
}
