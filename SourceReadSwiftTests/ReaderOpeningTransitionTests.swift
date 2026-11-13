import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderOpeningTransitionTests: XCTestCase {
    private func renderDirectSurface(for bookID: String, width: CGFloat) async throws -> UIImage {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        let parent = UIViewController()
        window.rootViewController = parent
        window.makeKeyAndVisible()
        let paperRaw = UserDefaults.standard.string(forKey: "reader.background") ?? ReaderBackground.white.rawValue
        let paper = ReaderOverrideStore.shared.override(for: bookID)?.background
            ?? ReaderBackground(rawValue: paperRaw) ?? .paper
        let host = UIHostingController(
            rootView: paper.color(isNight: paper.isDark)
                .ignoresSafeArea()
                .readerOpeningContentReady(true)
        )
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 568)
        host.didMove(toParent: parent)
        defer {
            window.isHidden = true
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            previousWindow?.makeKey()
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: host.view.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
    }

    func testBookSpecificDarkPaperIsAlreadyAppliedWithoutIntroSplash() async throws {
        let previous = UserDefaults.standard.object(forKey: "reader.background")
        let targetID = "opening-dark-" + UUID().uuidString
        UserDefaults.standard.set(ReaderBackground.white.rawValue, forKey: "reader.background")
        ReaderOverrideStore.shared.setOverride(BookReaderOverride(background: .dark), for: targetID)
        defer {
            UserDefaults.standard.set(previous, forKey: "reader.background")
            ReaderOverrideStore.shared.clearOverride(for: targetID)
        }
        let image = try await renderDirectSurface(for: targetID, width: 390)
        let cgImage = try XCTUnwrap(image.cgImage)
        var rgba = [UInt8](repeating: 0, count: 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: -4, y: -4, width: 390, height: 568))
        }
        XCTAssertEqual(rgba, [0, 0, 0, 255], "A saved dark book must render directly on dark paper without flashing an intro card")
    }

    func testOpeningReadinessRecordsReceiptImmediately() {
        let session = ReaderNavigationSession(bookID: "book-ready-check")
        XCTAssertFalse(session.isContentReady)
        session.recordReadyReceipt()
        XCTAssertTrue(session.isContentReady)
    }
}
