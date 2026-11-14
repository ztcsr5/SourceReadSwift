import SwiftUI
import XCTest
@testable import SourceReadSwift

final class Release117WallpaperEditorTests: XCTestCase {
    @MainActor func testWallpaperRendererSwitchesBetweenSavedDayAndNightDimming() {
        let image = makeImage()
        let view = ReaderWallpaperUIImageView(frame: CGRect(x: 0, y: 0, width: 120, height: 200))
        let adjustment = ReaderWallpaperAdjustment(dimming: 0.12, nightDimming: 0.62, usesLightText: true)
        for (night, expected) in [(false, 0.12), (true, 0.62), (false, 0.12)] {
            view.configure(image: image, fillMode: .fill, adjustment: adjustment, isNight: night)
            view.layoutIfNeeded()
            XCTAssertEqual(view.appliedDimming, CGFloat(expected), accuracy: 0.001)
        }
    }

    func testMiniaturePreviewPreservesTheRealReaderCropAtEveryAspectRatio() {
        for viewport in [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            let preview = ReaderWallpaperLayoutPolicy.previewSize(viewport: viewport, available: CGSize(width: 280, height: 320))
            XCTAssertEqual(preview.width / preview.height, viewport.width / viewport.height, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(preview.width, 280); XCTAssertLessThanOrEqual(preview.height, 320)
            var adjustment = ReaderWallpaperAdjustment(); adjustment.zoom = 1.7; adjustment.horizontalOffset = 0.5
            let source = CGSize(width: 1600, height: 400)
            let full = adjustment.imageFrame(imageSize: source, viewport: viewport, mode: .fill)
            let small = adjustment.imageFrame(imageSize: source, viewport: preview, mode: .fill)
            let scale = preview.width / viewport.width
            XCTAssertEqual(small.minX, full.minX * scale, accuracy: 0.01)
            XCTAssertEqual(small.minY, full.minY * scale, accuracy: 0.01)
            XCTAssertEqual(small.width, full.width * scale, accuracy: 0.01)
        }
    }

    func testNormalizedCropStaysInsideViewportWithoutChangingContainerSize() throws {
        for viewport in [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            for imageSize in [CGSize(width: 1600, height: 400), CGSize(width: 400, height: 1600)] {
                for offset in [-1.0, 0, 1] {
                    var adjustment = ReaderWallpaperAdjustment()
                    adjustment.zoom = 2; adjustment.horizontalOffset = offset; adjustment.verticalOffset = offset
                    try adjustment.validate()
                    let frame = adjustment.imageFrame(imageSize: imageSize, viewport: viewport, mode: .fill)
                    XCTAssertLessThanOrEqual(frame.minX, 0.01); XCTAssertLessThanOrEqual(frame.minY, 0.01)
                    XCTAssertGreaterThanOrEqual(frame.maxX, viewport.width - 0.01)
                    XCTAssertGreaterThanOrEqual(frame.maxY, viewport.height - 0.01)
                }
            }
        }
        var invalid = ReaderWallpaperAdjustment(); invalid.zoom = .nan
        XCTAssertThrowsError(try invalid.validate())
        invalid.zoom = 1; invalid.dimming = 2
        XCTAssertThrowsError(try invalid.validate())
    }

    func testAtomicImageAndAdjustmentRoundTripRejectsInvalidOverwriteAndKeepsLegacy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ReaderWallpaperRepository(rootURL: root)
        let image = makeImage()
        let legacy = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        try legacy.write(to: repository.legacyURL)
        XCTAssertNotNil(try repository.load(), "The existing single-JPEG format must remain readable")
        var adjustment = ReaderWallpaperAdjustment()
        adjustment.zoom = 1.8; adjustment.horizontalOffset = -0.4; adjustment.verticalOffset = 0.25
        adjustment.dimming = 0.2; adjustment.usesLightText = true; adjustment.fillMode = .fit
        _ = try repository.save(image: image, adjustment: adjustment)
        let committed = try Data(contentsOf: repository.recordURL)
        let reopened = try XCTUnwrap(ReaderWallpaperRepository(rootURL: root).load())
        XCTAssertEqual(reopened.adjustment, adjustment)
        XCTAssertGreaterThan(reopened.image.size.width, 0)
        XCTAssertEqual(try Data(contentsOf: repository.legacyURL), legacy, "Committing v2 must not destroy the old JPEG")
        var invalid = adjustment; invalid.zoom = 9
        XCTAssertThrowsError(try repository.save(image: image, adjustment: invalid))
        XCTAssertEqual(try Data(contentsOf: repository.recordURL), committed, "Rejected edits cannot replace the last good image/crop")
        try repository.clear(); try repository.clear()
        XCTAssertNil(try repository.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.legacyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.recordURL.path))
    }

    func testImageDecodeRejectsInvalidAndOversizedInputs() {
        XCTAssertThrowsError(try ReaderWallpaperRepository.decodeImage(Data("not an image".utf8)))
        XCTAssertThrowsError(try ReaderWallpaperRepository.decodeImage(Data(repeating: 0, count: 20_000_001)))
    }

    @MainActor func testEditorPreviewsNarrowAndNormalWithoutImplicitSave() async throws {
        let existed = ReaderCustomWallpaperStore.hasEditedWallpaper
        for width: CGFloat in [320, 390] {
            let draft = ReaderWallpaperDraft(image: makeImage(), adjustment: .init())
            let host = UIHostingController(rootView: ReaderWallpaperEditorView(draft: draft, onApply: { XCTFail("A passive preview must not save/apply") }))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = UIScreen.main.bounds
            let parent = UIViewController(); window.rootViewController = parent; window.makeKeyAndVisible()
            parent.addChild(host); parent.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844); host.didMove(toParent: parent)
            try await Task.sleep(nanoseconds: 250_000_000)
            host.view.layoutIfNeeded()
            XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "release117-wallpaper-editor-\(Int(width))"
            attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true
        }
        XCTAssertEqual(ReaderCustomWallpaperStore.hasEditedWallpaper, existed)
    }

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 300), format: format).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 450, height: 300))
            UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 450, y: 0, width: 450, height: 300))
        }
    }
}
