import SwiftUI
import XCTest
@testable import SourceReadSwift

final class CoverGlassThemeTests: XCTestCase {
    @MainActor func testActualRendererPreparesBoundedBitmapAndReusesItAcrossPages() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 48))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 48, width: 96, height: 48))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try XCTUnwrap(original.pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        // Await the real preparation; VM scheduling and a cold CIContext are not a rendering deadline.
        let rendered = await CoverGlassBackdropStore.preparedImage(for: url)
        let prepared = try XCTUnwrap(rendered)
        let pixels = try XCTUnwrap(prepared.cgImage)
        XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), 96)
        XCTAssertNotEqual(prepared.pngData(), original.pngData())
        let cached = await CoverGlassBackdropStore.preparedImage(for: url)
        XCTAssertTrue(cached === prepared, "A second page reuses the same blurred bitmap")
    }

    @MainActor func testDisabledThemesNeverRenderAndSameCoverDoesNotRenderTwice() async throws {
        let renderer = SuspendedCoverRenderer()
        let store = CoverGlassBackdropStore { await renderer.render($0) }
        let url = URL(string: "https://fixture.invalid/cover-a.jpg")!
        store.setSource(url)
        let initialCount = await renderer.count
        XCTAssertEqual(initialCount, 0)
        store.setEnabled(true)
        try await waitUntil { await renderer.count == 1 }
        store.setSource(url)
        store.setEnabled(true)
        let bitmap = paint(.red)
        await renderer.finish(url, with: bitmap)
        try await waitUntil { store.image === bitmap }
        let finalCount = await renderer.count
        XCTAssertEqual(finalCount, 1)
        store.setEnabled(false)
        XCTAssertNil(store.image)
    }

    @MainActor func testLateOldCoverCannotOverwriteCurrentCoverAndEmptyShelfClearsIt() async throws {
        let renderer = SuspendedCoverRenderer()
        let store = CoverGlassBackdropStore { await renderer.render($0) }
        let first = URL(string: "https://fixture.invalid/cover-a.jpg")!
        let second = URL(string: "https://fixture.invalid/cover-b.jpg")!
        store.setEnabled(true)
        store.setSource(first)
        try await waitUntil { await renderer.count == 1 }
        store.setSource(second)
        try await waitUntil { await renderer.count == 2 }
        let blue = paint(.blue)
        await renderer.finish(second, with: blue)
        try await waitUntil { store.image === blue }
        await renderer.finish(first, with: paint(.red))
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(store.image === blue)
        store.setSource(nil)
        XCTAssertNil(store.image)
        store.setEnabled(false)
    }

    @MainActor func testMissingCoverFallsBackRatherThanKeepingAnUnrelatedPalette() async throws {
        let renderer = SuspendedCoverRenderer()
        let store = CoverGlassBackdropStore { await renderer.render($0) }
        let first = URL(string: "https://fixture.invalid/cover-a.jpg")!
        let url = URL(string: "https://fixture.invalid/missing.jpg")!
        store.setEnabled(true)
        store.setSource(first)
        try await waitUntil { await renderer.count == 1 }
        let red = paint(.red)
        await renderer.finish(first, with: red)
        try await waitUntil { store.image === red }
        store.setSource(url)
        try await waitUntil { await renderer.count == 2 }
        await renderer.finish(url, with: nil)
        try await waitUntil { store.image == nil }
        XCTAssertNil(store.image)
        store.setEnabled(false)
    }

    @MainActor private func paint(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 12)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
        }
    }

    @MainActor private func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<2_000 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Cover background did not reach the expected state")
    }
}

private actor SuspendedCoverRenderer {
    private var pending: [URL: CheckedContinuation<UIImage?, Never>] = [:]
    private(set) var count = 0

    func render(_ url: URL) async -> UIImage? {
        count += 1
        // Ignore cancellation deliberately to exercise a slow, stale cover completion.
        return await withCheckedContinuation { pending[url] = $0 }
    }

    func finish(_ url: URL, with image: UIImage?) {
        pending.removeValue(forKey: url)?.resume(returning: image)
    }
}
