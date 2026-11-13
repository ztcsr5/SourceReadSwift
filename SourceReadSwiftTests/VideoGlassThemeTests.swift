import SwiftUI
import XCTest
@testable import SourceReadSwift

final class VideoGlassThemeTests: XCTestCase {
    func testVideoGlassThemesAreAdditiveAndDoNotDisturbExistingFamilies() {
        XCTAssertEqual(AppVisualTheme.videoGlassThemes, [.videoAurora, .videoEmber])
        for theme in AppVisualTheme.videoGlassThemes {
            XCTAssertTrue(theme.isVideoGlass)
            XCTAssertTrue(theme.supportsLiveGlass, "视频玻璃主题需要实时玻璃采样，否则背景与卡片会脱节")
            XCTAssertNil(theme.illustratedPaper, "动态背景与插画纸面互斥")
            XCTAssertFalse(theme.title.isEmpty)
            XCTAssertFalse(theme.detail.isEmpty)
        }
        XCTAssertEqual(AppVisualTheme.allCases.filter(\.isVideoGlass).count, 2)
    }

    func testVideoGlassPalettesDifferLightAndDarkAndAcrossThemes() {
        let auroraLight = VideoGlassPalette(theme: .videoAurora, isDark: false)
        let auroraDark = VideoGlassPalette(theme: .videoAurora, isDark: true)
        let emberDark = VideoGlassPalette(theme: .videoEmber, isDark: true)
        // 两个主题必须真的不同色，否则"新增主题"只是换了名字。
        XCTAssertNotEqual(String(describing: auroraDark.primary), String(describing: emberDark.primary))
        XCTAssertNotEqual(String(describing: auroraLight.primary), String(describing: emberDark.primary))
    }

    func testVideoGlassSurvivesRoundTripThroughStoredSelection() throws {
        // 独立的 suite：theme selection 是全局 UserDefaults 键，直接改 .standard
        // 会污染同一进程里跑的其他主题测试。
        let suite = "video-glass-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for theme in AppVisualTheme.videoGlassThemes {
            defaults.set(theme.rawValue, forKey: AppVisualTheme.selectionKey)
            XCTAssertEqual(AppVisualTheme.selected(in: defaults), theme)
            AppVisualTheme.bootstrapSelection(in: defaults)
            XCTAssertEqual(AppVisualTheme.selected(in: defaults), theme)
        }
    }

    /// 视频感来自低频渐变；解码真实视频会长期占用解码器。这里锁住"只画不播"。
    func testBackdropStaysOnTimelineInsteadOfVideoPlayback() throws {
        let source = try String(contentsOfFile: #filePath
            .replacingOccurrences(of: "SourceReadSwiftTests/VideoGlassThemeTests.swift",
                                  with: "SourceReadSwift/Shared/DesignSystem/VideoGlassBackdrop.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("TimelineView(.animation"))
        XCTAssertFalse(source.contains("AVPlayer"))
        XCTAssertFalse(source.contains("AVPlayerLayer"))
        XCTAssertTrue(source.contains("accessibilityReduceMotion"), "必须尊重减弱动态效果")
        XCTAssertTrue(source.contains("TimelineView(.animation(paused: false))") || source.contains("minimumInterval: 1.0 / 20.0"))
    }
}
