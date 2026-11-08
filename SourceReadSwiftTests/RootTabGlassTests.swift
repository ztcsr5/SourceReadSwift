import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class RootTabGlassTests: XCTestCase {
    @MainActor func testTabAndSearchBorrowBackdropColourAtBothWidthsAndAppearances() async throws {
        XCTAssertFalse(UIAccessibility.isReduceTransparencyEnabled,
            "The native material fixture requires the runner's default transparency setting")
        for width in [CGFloat(320), 390] {
            for scheme in [ColorScheme.light, .dark] {
                let fixture = TabGlassFixture(width: width, scheme: scheme)
                let differences = try await backdropDifferences(fixture)
                for (surface, difference) in differences {
                    XCTAssertGreaterThan(difference, 5,
                        "\(width) \(scheme) \(surface) must reveal the backdrop; difference=\(difference)")
                }
            }
        }
    }

    @MainActor func testOpaqueAtelierBaselineDoesNotRevealBackdropColour() async throws {
        let differences = try await backdropDifferences(TabGlassFixture(usesOldOpaqueRecipe: true))
        for (surface, difference) in differences {
            XCTAssertLessThan(difference, 1,
                "The old solid \(surface) must be a negative control for the material sampler")
        }
    }

    @MainActor func testAccessibilityExplicitlyMakesBothSurfacesOpaque() async throws {
        for fixture in [TabGlassFixture(reducesTransparency: true),
                        TabGlassFixture(scheme: .dark, contrast: .increased)] {
            let differences = try await backdropDifferences(fixture)
            for (surface, difference) in differences {
                XCTAssertLessThan(difference, 1,
                    "Accessibility must make \(surface) independent of its backdrop")
            }
        }
    }

    @MainActor private func backdropDifferences(_ fixture: TabGlassFixture) async throws -> [String: Double] {
        let previousTheme = UserDefaults.standard.object(forKey: AppVisualTheme.selectionKey)
        UserDefaults.standard.set(AppVisualTheme.pineMist.rawValue, forKey: AppVisualTheme.selectionKey)
        defer {
            if let previousTheme { UserDefaults.standard.set(previousTheme, forKey: AppVisualTheme.selectionKey) }
            else { UserDefaults.standard.removeObject(forKey: AppVisualTheme.selectionKey) }
        }
        let warm = try await capture(fixture, backdrop: .red)
        let cool = try await capture(fixture, backdrop: .blue)
        let tabWidth = (fixture.width - 98) / 3
        let samples: [String: CGRect] = [
            "tab": CGRect(x: 16 + tabWidth + 10, y: 192, width: 6, height: 8),
            "search": CGRect(x: fixture.width - 56, y: 192, width: 5, height: 8)
        ]
        return try samples.mapValues { rect in
            let first = try channels(warm, in: rect), second = try channels(cool, in: rect)
            return zip(first, second).map { abs($0 - $1) }.reduce(0, +) / 3
        }
    }

    @MainActor private func capture(_ fixture: TabGlassFixture, backdrop: Color) async throws -> UIImage {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = CGRect(x: 0, y: 0, width: fixture.width, height: 480)
        window.overrideUserInterfaceStyle = fixture.scheme == .dark ? .dark : .light
        let host = UIHostingController(rootView: TabGlassBackdrop(fixture: fixture, backdrop: backdrop))
        host.overrideUserInterfaceStyle = window.overrideUserInterfaceStyle
        let parent = UIViewController()
        window.rootViewController = parent
        parent.addChild(host)
        parent.setOverrideTraitCollection(UITraitCollection(accessibilityContrast:
            fixture.contrast == .increased ? .high : .normal), forChild: host)
        parent.view.addSubview(host.view)
        host.view.frame = window.bounds
        host.didMove(toParent: parent)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 250_000_000)
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: host.view.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: picture)
        attachment.name = "root-tab-glass-\(fixture.width)-\(fixture.scheme)-\(fixture.reducesTransparency)-\(fixture.contrast)-\(fixture.usesOldOpaqueRecipe)-\(backdrop)"
        attachment.lifetime = .keepAlways
        add(attachment)
        return picture
    }

    private func channels(_ image: UIImage, in rect: CGRect) throws -> [Double] {
        let picture = try XCTUnwrap(image.cgImage)
        let width = picture.width, height = picture.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        XCTAssertTrue(rendered)
        var totals = [0.0, 0.0, 0.0], count = 0.0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                for channel in 0..<3 { totals[channel] += Double(pixels[(y * width + x) * 4 + channel]) }
                count += 1
            }
        }
        return totals.map { $0 / count }
    }
}

private struct TabGlassFixture {
    var width: CGFloat = 390
    var scheme: ColorScheme = .light
    var reducesTransparency = false
    var contrast: ColorSchemeContrast = .standard
    var usesOldOpaqueRecipe = false
}

private struct TabGlassBackdrop: View {
    let fixture: TabGlassFixture
    let backdrop: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            Group {
                if fixture.usesOldOpaqueRecipe {
                    // This is the previous atelier background recipe, without glyphs.
                    HStack(spacing: 10) {
                        Capsule().fill(AppTheme.card).frame(height: 54)
                        Circle().fill(AppTheme.prominentFill)
                            .frame(width: 52, height: 52)
                    }.padding(.horizontal, 12).padding(.bottom, 6)
                } else {
                    LegacyTabBar(selection: .constant(0), onSearch: {})
                }
            }.frame(width: fixture.width).offset(y: 170)
        }
        .frame(width: fixture.width, height: 480)
        .environment(\.colorScheme, fixture.scheme)
        .environment(\.accessibilityReduceTransparency, fixture.reducesTransparency)
        .environment(\.colorSchemeContrast, fixture.contrast)
        .ignoresSafeArea()
    }
}
