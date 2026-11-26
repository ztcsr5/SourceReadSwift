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

    @MainActor func testActualRendererSeparatesHeaderContextsAndReusesAnIdenticalContext() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try XCTUnwrap(paint(.green).pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let firstHeaders = ["Referer": "https://first.example/", "Accept": "image/*"]
        let firstRendered = await CoverGlassBackdropStore.preparedImage(for: url, headers: firstHeaders)
        let first = try XCTUnwrap(firstRendered)
        let secondRendered = await CoverGlassBackdropStore.preparedImage(for: url,
            headers: ["Referer": "https://second.example/", "Accept": "image/*"])
        let second = try XCTUnwrap(secondRendered)
        XCTAssertFalse(first === second, "The same URL from another source has a separate request context")
        let reused = await CoverGlassBackdropStore.preparedImage(for: url,
            headers: ["Accept": "image/*", "Referer": "https://first.example/"])
        XCTAssertTrue(first === reused, "Header ordering must not trigger another render")
    }

    @MainActor func testHeaderChangeForTheSameCoverRefreshesThePreparedBackground() async throws {
        let first = paint(.red)
        let second = paint(.blue)
        let renderer = ContextualCoverRenderer(first: first, second: second)
        let store = CoverGlassBackdropStore(renderWithHeaders: { await renderer.render($0, headers: $1) })
        let url = URL(string: "https://fixture.invalid/same-cover.jpg")!
        store.setEnabled(true)
        store.setSource(url, headers: ["Referer": "https://first.example/"])
        try await waitUntil { store.image === first }
        store.setSource(url, headers: ["Referer": "https://second.example/"])
        try await waitUntil { store.image === second }
        store.setSource(url, headers: ["Referer": "https://second.example/"])
        let count = await renderer.count
        XCTAssertEqual(count, 2)
        store.setEnabled(false)
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

    @MainActor func testLightCoverRetainsItsHueAboveTheShelfAndFadesBelow() async throws {
        let terracotta = paint(UIColor(red: 0.78, green: 0.26, blue: 0.16, alpha: 1))
        let store = CoverGlassBackdropStore { _ in terracotta }
        store.setSource(URL(fileURLWithPath: "/fixture-cover"))
        store.setEnabled(true)
        try await waitUntil { store.image === terracotta }
        let wash = CoverGlassBackdrop(backdrop: store).frame(width: 120, height: 240)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: wash)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let top = try sample(image, x: 60, y: 24)
        let shelf = try sample(image, x: 60, y: 224)
        XCTAssertGreaterThan(top[0] - top[1], 50, "A heavy white veil erases the cover's warm midtones")
        XCTAssertGreaterThan(shelf[1] - top[1], 40)
        XCTAssertGreaterThan(top[0] - top[1], 2 * (shelf[0] - shelf[1]))
    }

    @MainActor func testMistPapersKeepTheBodyNearWhiteAndTheirEdgeDistinct() throws {
        for paper in [ReaderBackground.mistLeaf, .mistSky, .mistRose] {
            let renderer = ImageRenderer(content: ReaderPaperTextureView(background: paper, night: false)
                .frame(width: 120, height: 240))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            let edge = try sample(image, x: 6, y: 74)
            let body = try sample(image, x: 94, y: 178)
            XCTAssertGreaterThanOrEqual(body.min() ?? 0, 249, paper.title)
            XCTAssertGreaterThanOrEqual(edge.min() ?? 0, 230, paper.title)
            XCTAssertLessThan(edge.min() ?? 255, body.min() ?? 0, paper.title)
            let dominant = paper == .mistLeaf ? 1 : paper == .mistSky ? 2 : 0
            XCTAssertEqual(edge[dominant], edge.max(), paper.title)
        }
    }

    private func sample(_ image: CGImage, x: Int, y: Int) throws -> [Int] {
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba.prefix(3).map(Int.init)
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

private actor ContextualCoverRenderer {
    let first: UIImage
    let second: UIImage
    private(set) var count = 0

    init(first: UIImage, second: UIImage) {
        self.first = first
        self.second = second
    }

    func render(_ url: URL, headers: [String: String]) -> UIImage {
        count += 1
        return headers["Referer"] == "https://first.example/" ? first : second
    }
}
