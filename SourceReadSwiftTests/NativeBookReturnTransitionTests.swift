import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class NativeBookReturnTransitionTests: XCTestCase {
    @MainActor func testNativeSourceOwnershipCannotRemoveANewerCover() {
        let handoff = ReadingCoverHandoff()
        let old = UIView(), next = UIView()
        handoff.registerNativeCover(old, for: "same-book")
        handoff.registerNativeCover(next, for: "same-book")
        handoff.removeNativeCover(old, for: "same-book")
        XCTAssertTrue(handoff.nativeCover(for: "same-book") === next)
        handoff.removeNativeCover(next, for: "same-book")
        XCTAssertNil(handoff.nativeCover(for: "same-book"))
    }

    @MainActor func testBookAlignmentUsesMountedCoordinatesAndRejectsMissingGeometry() {
        let controller = UIViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let book = UIView(frame: CGRect(x: 124, y: 230, width: 142, height: 190))
        XCTAssertNil(BookReturnGeometry.alignment(of: book, in: controller))
        controller.view.addSubview(book)
        XCTAssertEqual(BookReturnGeometry.alignment(of: book, in: controller), book.frame)
        book.bounds.size = .zero
        XCTAssertNil(BookReturnGeometry.alignment(of: book, in: controller))
    }

    @MainActor func testNativeReturnOptionsKeepAFallbackAndRestoreTheirOwner() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("Native zoom requires iOS18") }
        let controller = UIViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let book = UIView(frame: CGRect(x: 124, y: 230, width: 142, height: 190))
        controller.view.addSubview(book)
        let original = UIViewController.Transition.crossDissolve
        controller.preferredTransition = original
        let handoff = ReadingCoverHandoff()
        let transition = NativeBookReturnTransition(sourceID: "book", handoff: handoff)
        transition.install(in: controller, anchor: book)
        XCTAssertTrue(controller.preferredTransition === original, "A missing source keeps the existing transition")
        let source = UIView(frame: CGRect(x: 0, y: 0, width: 152, height: 202))
        handoff.registerNativeCover(source, for: "book")
        transition.install(in: controller, anchor: book)
        XCTAssertNotNil(controller.preferredTransition)
        XCTAssertFalse(controller.preferredTransition === original)
        transition.restore()
        XCTAssertTrue(controller.preferredTransition === original)
        transition.install(in: controller, anchor: book)
        transition.restore(prefersDefault: true)
        XCTAssertNil(controller.preferredTransition, "The app's reduced-motion fallback must not reinstall zoom")
    }

    @MainActor func testMountedNativeCoverUsesTheSameDecodedFrameAndActualDisplaySize() async throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("Native zoom source requires iOS18") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600), format: format).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        let handoff = ReadingCoverHandoff()
        let host = UIHostingController(rootView: AsyncBookCover(urlString: url.absoluteString, width: 152, height: 202,
            prefersDeskRaster: true, cornerRadius: 3, nativeSourceID: "book")
            .environment(\.readingCoverHandoff, handoff).environment(\.displayScale, 1))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for _ in 0..<100 {
            if let source = handoff.nativeCover(for: "book"), !source.bounds.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        host.view.layoutIfNeeded()
        let source = try XCTUnwrap(handoff.nativeCover(for: "book") as? UIImageView)
        XCTAssertEqual(source.bounds.width, 152, accuracy: 1)
        XCTAssertEqual(source.bounds.height, 202, accuracy: 1)
        XCTAssertTrue(source.image === handoff.image(for: url), "No second decoder or screenshot is allowed")
        XCTAssertEqual(source.image?.cgImage?.height, 243)
    }
}
