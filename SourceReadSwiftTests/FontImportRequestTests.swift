import XCTest
import UIKit
@testable import SourceReadSwift

final class FontImportRequestTests: XCTestCase {
    func testSandboxCopyDoesNotReenterProviderCoordination() {
        let root = URL(fileURLWithPath: "/private/reader-sandbox")
        XCTAssertFalse(FontImportOperation.requiresCoordination(source: root.appendingPathComponent("tmp/Inbox/font.ttf"), sandbox: root))
        XCTAssertTrue(FontImportOperation.requiresCoordination(source: URL(fileURLWithPath: "/private/reader-sandbox-other/font.ttf"), sandbox: root))
        XCTAssertTrue(FontImportOperation.requiresCoordination(source: URL(string: "https://invalid/font.ttf")!, sandbox: root))
    }

    func testDeadlineDoesNotAwaitABlockedWorker() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let started = Date()
        do {
            _ = try await FontImportRequest.perform(timeout: 0.04, operation: { _ in
                gate.wait()
                return CustomFontItem(fileName: "late.ttf", displayName: "Late", postScriptName: "Late", fileSize: 12)
            })
            XCTFail("A blocked worker cannot report success before the deadline")
        } catch { XCTAssertEqual((error as NSError).code, 8) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "Do not use a task group that waits for uncooperative IO")
    }

    func testCancelledRequestDiscardsAnUncooperativeWorkersLateSuccess() async throws {
        let entered = expectation(description: "Worker entered before cancellation")
        let discarded = expectation(description: "Late candidate is discarded, not silently installed")
        let gate = DispatchSemaphore(value: 0)
        let work = Task {
            try await FontImportRequest.perform(operation: { _ in
                entered.fulfill(); gate.wait()
                return CustomFontItem(fileName: "late.ttf", displayName: "Late", postScriptName: "Late", fileSize: 12)
            }, discard: { _ in discarded.fulfill() })
        }
        await fulfillment(of: [entered], timeout: 2)
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled work must not publish a late candidate") }
        catch { XCTAssertTrue(error is CancellationError) }
        gate.signal()
        await fulfillment(of: [discarded], timeout: 2)
    }

    func testCancellationFinishesWithoutPublishingTheWorkerResult() async throws {
        let entered = expectation(description: "Worker entered")
        let gate = DispatchSemaphore(value: 0)
        let work = Task {
            try await FontImportRequest.perform(operation: { cancellation in
                entered.fulfill(); gate.wait(); try cancellation.check()
                return CustomFontItem(fileName: "cancel.ttf", displayName: "Cancel", postScriptName: "Cancel", fileSize: 12)
            })
        }
        await fulfillment(of: [entered], timeout: 2)
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled work must not enable a font") }
        catch { XCTAssertTrue(error is CancellationError) }
        gate.signal()
    }

    @MainActor func testTwelveMegabyteLocalTTFFromAPickerCopyImportsWithoutDismissal() async throws {
        let bundledNames = ["MaShanZheng-Regular", "ZhiMangXing-Regular"]
        let priorLocations = bundledNames.map { CustomFontLocations.file(for: $0) }
        defer {
            for (name, prior) in zip(bundledNames, priorLocations) {
                if let prior { CustomFontLocations.register(postScriptName: name, file: prior) }
                else { CustomFontLocations.remove(name) }
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bundled = try XCTUnwrap(Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil)?.first)
        var bytes = try Data(contentsOf: bundled)
        if bytes.count < 12 * 1024 * 1024 { bytes.append(Data(count: 12 * 1024 * 1024 - bytes.count)) }
        let picked = root.appendingPathComponent("QQ-local-copy.ttf"); try bytes.write(to: picked)
        let fonts = CustomFontManager(rootURL: root.appendingPathComponent("installed"))
        let item = try await fonts.importPickedFont(from: picked)
        XCTAssertEqual(item.fileSize, Int64(bytes.count))
        XCTAssertEqual(fonts.installedFonts.map(\.postScriptName), [item.postScriptName])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fonts.fontsDirectory.appendingPathComponent(item.fileName).path))
        CustomFontLocations.remove(item.postScriptName)
        let directory = fonts.fontsDirectory
        let restored = try await FontImportRequest.perform(operation: { cancellation in
            try FontImportOperation.restoreInstalled(name: item.postScriptName, directory: directory, cancellation: cancellation)
        })
        XCTAssertEqual(restored.postScriptName, item.postScriptName)
        XCTAssertEqual(restored.fileName, item.fileName, "Relaunch restoration must not make another 12 MB copy")
        XCTAssertNotNil(UIFont(name: restored.postScriptName, size: 20))
    }
}
