import Combine
import SwiftUI
import UIKit

/// Paired external UIKit alternate icon + internal BrandMark image asset so
/// Settings headers, About view, and Appearance previews always mirror the home screen icon.
enum AppIconOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case forest = "AppIcon"
    case classic = "AppIconClassic"
    case klein = "AppIconKlein"
    case shuimo = "AppIconShuimo"
    case wuxia = "AppIconWuxia"
    case anime = "AppIconAnime"
    case kawaii = "AppIconKawaii"
    case noir = "AppIconNoir"

    static let storageKey = "settings.appIconName"

    var id: String { rawValue }

    /// Pass `nil` to UIKit to restore the primary `AppIcon`.
    var uiKitIconName: String? {
        self == .forest ? nil : rawValue
    }

    var brandMarkAssetName: String {
        switch self {
        case .forest: return "BrandMark"
        case .classic: return "BrandMarkClassic"
        case .klein: return "BrandMarkKlein"
        case .shuimo: return "BrandMarkShuimo"
        case .wuxia: return "BrandMarkWuxia"
        case .anime: return "BrandMarkAnime"
        case .kawaii: return "BrandMarkKawaii"
        case .noir: return "BrandMarkNoir"
        }
    }

    var title: String {
        switch self {
        case .forest: return "森林绿 · 默认"
        case .classic: return "原初 · 白紫"
        case .klein: return "蓝艾 · 静谧"
        case .shuimo: return "水墨 · 朱印"
        case .wuxia: return "江湖 · 剑青"
        case .anime: return "晴空 · 樱蓝"
        case .kawaii: return "甜心 · 手账"
        case .noir: return "极夜 · 曜石"
        }
    }

    var subtitle: String {
        switch self {
        case .forest: return "折序经典主标 · 纯白与森林绿"
        case .classic: return "paperfold 紫色经典双色调"
        case .klein: return "克莱因蓝 · 清晰书刊徽标"
        case .shuimo: return "宣纸松烟墨 · 朱砂印章落款"
        case .wuxia: return "玄铁与剑青 · 金线流刃"
        case .anime: return "晴空浅蓝 × 樱粉星芒"
        case .kawaii: return "奶油草莓 × 抹茶圆印"
        case .noir: return "曜石深黑 · 银灰极夜折痕"
        }
    }

    var previewPaperHex: UInt32 {
        switch self {
        case .forest: return 0xFFFFFF
        case .classic: return 0xF6F3FA
        case .klein: return 0xEEF4FA
        case .shuimo: return 0xF4EFE4
        case .wuxia: return 0x141D22
        case .anime: return 0xEAF4FF
        case .kawaii: return 0xFFF7F1
        case .noir: return 0x101216
        }
    }

    var previewInkHex: UInt32 {
        switch self {
        case .forest: return 0x3D6348
        case .classic: return 0x594FDB
        case .klein: return 0x1842B8
        case .shuimo: return 0x22272A
        case .wuxia: return 0x58AE9E
        case .anime: return 0xE56B94
        case .kawaii: return 0xE06D88
        case .noir: return 0xD9DDE4
        }
    }

    static func resolved(rawValue: String?) -> AppIconOption {
        guard let rawValue, !rawValue.isEmpty else { return .forest }
        return AppIconOption(rawValue: rawValue) ?? .forest
    }

    static func current(in defaults: UserDefaults = .standard) -> AppIconOption {
        resolved(rawValue: defaults.string(forKey: storageKey))
    }

    static func resolvedBrandAssetName(in defaults: UserDefaults = .standard) -> String {
        current(in: defaults).brandMarkAssetName
    }

    static func recommended(for theme: AppVisualTheme) -> AppIconOption {
        switch theme {
        case .forest: return .forest
        case .classic: return .classic
        case .kleinSage: return .klein
        case .inkwash, .shuimo: return .shuimo
        case .wuxia: return .wuxia
        case .anime: return .anime
        case .kawaii: return .kawaii
        case .custom: return .classic
        }
    }
}

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published private(set) var currentOption: AppIconOption
    @Published var statusMessage: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.currentOption = AppIconOption.current(in: defaults)
        syncFromUIKitIfNeeded()
    }

    func syncFromUIKitIfNeeded() {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        if let activeName = UIApplication.shared.alternateIconName,
           let option = AppIconOption(rawValue: activeName) {
            if currentOption != option {
                currentOption = option
                defaults.set(option.rawValue, forKey: AppIconOption.storageKey)
            }
        }
    }

    @discardableResult
    func select(_ option: AppIconOption) async -> Bool {
        currentOption = option
        defaults.set(option.rawValue, forKey: AppIconOption.storageKey)
        defaults.set(defaults.integer(forKey: "settings.appearanceRevision") + 1,
                     forKey: "settings.appearanceRevision")
        statusMessage = nil

        guard UIApplication.shared.supportsAlternateIcons else {
            statusMessage = "已同步应用内图标；当前环境不支持更换桌面图标。"
            return true
        }

        if UIApplication.shared.alternateIconName == option.uiKitIconName {
            return true
        }

        do {
            try await UIApplication.shared.setAlternateIconName(option.uiKitIconName)
            return true
        } catch {
            // Keep the internal icon active on fallback hosts (such as unsigned test runners)
            // while surfacing a concise non-fatal message to the user.
            statusMessage = "应用内图标已切换；桌面图标切换受系统签名或限制（\(error.localizedDescription)）。"
            return false
        }
    }

    /// Deterministic test/storage hook that updates internal state and UserDefaults synchronously.
    static func applySelection(_ option: AppIconOption, in defaults: UserDefaults = .standard) {
        defaults.set(option.rawValue, forKey: AppIconOption.storageKey)
        if defaults === UserDefaults.standard {
            shared.currentOption = option
            defaults.set(defaults.integer(forKey: "settings.appearanceRevision") + 1,
                         forKey: "settings.appearanceRevision")
        }
    }
}
