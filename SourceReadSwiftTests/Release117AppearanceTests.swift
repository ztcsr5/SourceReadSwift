import SwiftUI
import XCTest
@testable import SourceReadSwift

final class Release117AppearanceTests: XCTestCase {
    @MainActor func testSystemModeTracksLiveWindowTraitChanges() async throws {
        try await check(mode: .system, expected: [.light, .dark, .light])
    }

    @MainActor func testExplicitDarkModeStillOverridesSystem() async throws {
        try await check(mode: .dark, expected: [.dark, .dark, .dark])
    }

    @MainActor private func check(mode: ThemeMode, expected: [ColorScheme]) async throws {
        var observed: ColorScheme?
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        let root = SchemeProbe { observed = $0 }.modifier(AppColorSchemePreference(mode: mode))
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for (index, style) in [UIUserInterfaceStyle.light, .dark, .light].enumerated() {
            window.overrideUserInterfaceStyle = style
            for _ in 0..<30 {
                if observed == expected[index] { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(observed, expected[index], "Mode \(mode), system trait \(style)")
        }
    }
}

private struct SchemeProbe: View {
    @Environment(\.colorScheme) private var scheme
    let report: (ColorScheme) -> Void
    var body: some View {
        Color.clear.onAppear { report(scheme) }.onChange(of: scheme) { report($0) }
    }
}
