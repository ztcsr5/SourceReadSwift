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
    case inPageGlass = "AppIconInPageGlass"
    case atelierRing = "AppIconAtelierRing"
    case shuimoPeak = "AppIconShuimoPeak"
    case wuxiaSword = "AppIconWuxiaSword"

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
        case .inPageGlass: return "BrandMarkInPageGlass"
        case .atelierRing: return "BrandMarkAtelierRing"
        case .shuimoPeak: return "BrandMarkShuimoPeak"
        case .wuxiaSword: return "BrandMarkWuxiaSword"
        }
    }

    var title: String {
        switch self {
        case .forest: return "森林绿 · 默认"
        case .classic: return "原初 · 白紫"
        case .klein: return "蓝艾 · 静谧"
        case .shuimo: return "雾纸 · 墨山"
        case .wuxia: return "断锋 · 飞白"
        case .anime: return "晴空 · 樱蓝"
        case .kawaii: return "兔兔 · 莓果"
        case .noir: return "极夜 · 曜石"
        case .inPageGlass: return "琉璃 · 旧版"
        case .atelierRing: return "色环 · 旧版"
        case .shuimoPeak: return "墨峰 · 旧版"
        case .wuxiaSword: return "双剑 · 旧版"
        }
    }

    var subtitle: String {
        switch self {
        case .forest: return "折序经典主标 · 纯白与森林绿"
        case .classic: return "paperfold 紫色经典双色调"
        case .klein: return "克莱因蓝 · 清晰书刊徽标"
        case .shuimo: return "白宣、烟墨与一线山形"
        case .wuxia: return "黑白飞白 · 干笔锋线"
        case .anime: return "晴空浅蓝 × 樱粉星芒"
        case .kawaii: return "莓果书与软耳阅读兔"
        case .noir: return "曜石深黑 · 银灰极夜折痕"
        case .inPageGlass: return "InPage v1.0.0 · 半透紫蓝琉璃折页"
        case .atelierRing: return "Atelier · 莫兰迪拼色立体圆环"
        case .shuimoPeak: return "素笺圆环墨峰 · 独立手绘旧版"
        case .wuxiaSword: return "玄铁黑底交叉双剑 · 独立旧版"
        }
    }

    var previewPaperHex: UInt32 {
        switch self {
        case .forest: return 0xFFFFFF
        case .classic: return 0xF6F3FA
        case .klein: return 0xEEF4FA
        case .shuimo: return 0xF4F4F4
        case .wuxia: return 0x101010
        case .anime: return 0xEAF4FF
        case .kawaii: return 0xFFE9EB
        case .noir: return 0x101216
        case .inPageGlass: return 0xF5F6FA
        case .atelierRing: return 0x3A2D2E
        case .shuimoPeak: return 0xF4F4F4
        case .wuxiaSword: return 0x101010
        }
    }

    var previewInkHex: UInt32 {
        switch self {
        case .forest: return 0x3D6348
        case .classic: return 0x594FDB
        case .klein: return 0x1842B8
        case .shuimo: return 0x242424
        case .wuxia: return 0xF6F6F6
        case .anime: return 0xE56B94
        case .kawaii: return 0x9A2854
        case .noir: return 0xD9DDE4
        case .inPageGlass: return 0x3E49B8
        case .atelierRing: return 0xB8A6CE
        case .shuimoPeak: return 0x222222
        case .wuxiaSword: return 0xECECEC
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
        case .forest, .paper, .coverGlass, .porcelain: return .forest
        case .classic: return .classic
        case .kleinSage: return .klein
        case .inkwash, .shuimo, .inkstone, .pineSootMagazine: return .shuimo
        case .hardcoverStudy: return .classic
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
    @Published private(set) var homeScreenShortcutSuggestion: AppIconOption?
    @Published private(set) var isSelecting = false

    private let defaults: UserDefaults
    private let systemIcon: SystemIconAccess

    struct SystemIconAccess {
        let isSupported: @MainActor () -> Bool
        let currentName: @MainActor () -> String?
        let setName: @MainActor (String?) async throws -> Void
        var isActive: @MainActor () -> Bool = { true }
        var isDeclared: @MainActor (String) -> Bool = { _ in true }
        var isContainer: @MainActor () -> Bool = { false }

        static let live = Self(
            isSupported: { UIApplication.shared.supportsAlternateIcons },
            currentName: { UIApplication.shared.alternateIconName },
            setName: { try await UIApplication.shared.setAlternateIconName($0) },
            isActive: { UIApplication.shared.applicationState == .active },
            isDeclared: {
                AppIconManager.declaresAlternateIcon($0, in: Bundle.main.infoDictionary ?? [:],
                    isPad: UIDevice.current.userInterfaceIdiom == .pad)
            },
            isContainer: { SandboxEnvironment.isLiveContainer }
        )
    }

    init(defaults: UserDefaults = .standard, systemIcon: SystemIconAccess? = nil) {
        self.defaults = defaults
        self.systemIcon = systemIcon ?? .live
        self.currentOption = AppIconOption.current(in: defaults)
        syncFromUIKitIfNeeded()
    }

    func syncFromUIKitIfNeeded() {
        guard !isContainer, systemIcon.isSupported() else { return }
        commitIcon(AppIconOption.resolved(rawValue: systemIcon.currentName()))
    }

    var isContainer: Bool { systemIcon.isContainer() }

    /// Confirms an actual system icon for independent installs; a guest selects only its local artwork.
    @discardableResult
    func select(_ option: AppIconOption) async -> Bool {
        guard !isSelecting else { return false }
        statusMessage = nil
        homeScreenShortcutSuggestion = nil
        if isContainer {
            commitExplicitSelection(option)
            homeScreenShortcutSuggestion = option
            statusMessage = "已换 App 内徽标。LiveContainer 无法用系统 API 直接改桌面图标，请从主屏幕入口导出同款图，旧快捷指令图标不会自动更新。"
            return true
        }
        if let target = option.uiKitIconName, !systemIcon.isDeclared(target) {
            statusMessage = "安装包未声明此桌面图标。请用与此版本匹配的完整安装包。"
            return false
        }
        guard systemIcon.isSupported() else {
            statusMessage = "iOS 未开放桌面换图标，已保留当前图标。"
            homeScreenShortcutSuggestion = option
            return false
        }
        guard systemIcon.isActive() else {
            statusMessage = "请回到纸间后再选一次。"
            return false
        }

        isSelecting = true
        defer { isSelecting = false }
        let target = option.uiKitIconName
        do {
            if systemIcon.currentName() != target {
                try await systemIcon.setName(target)
            }
            guard systemIcon.currentName() == target else {
                syncFromUIKitIfNeeded()
                statusMessage = "iOS 未确认桌面图标切换，已保留系统当前图标。"
                return false
            }
            commitExplicitSelection(option)
            return true
        } catch {
            syncFromUIKitIfNeeded()
            let failure = error as NSError
            let details = "\(failure.domain) \(failure.code)"
            if failure.domain == NSOSStatusErrorDomain, failure.code == -54 {
                homeScreenShortcutSuggestion = option
                statusMessage = "iOS 未更改桌面图标（\(details)）。可以导出这款图标，给主屏幕快捷指令使用。"
            } else {
                statusMessage = "桌面图标未切换（\(details)）。"
            }
            return false
        }
    }

    static func declaresAlternateIcon(_ name: String, in manifest: [String: Any], isPad: Bool) -> Bool {
        // The iPad override, when present, is authoritative for that idiom.
        let deviceIcons = isPad ? manifest["CFBundleIcons~ipad"] : nil
        guard let icons = (deviceIcons ?? manifest["CFBundleIcons"]) as? [String: Any],
              let alternates = icons["CFBundleAlternateIcons"] as? [String: [String: Any]],
              let entry = alternates[name] else { return false }
        return entry["CFBundleIconName"] as? String == name ||
            (entry["CFBundleIconFiles"] as? [String])?.contains(where: { !$0.isEmpty }) == true
    }

    private func commitIcon(_ option: AppIconOption) {
        guard currentOption != option || AppIconOption.current(in: defaults) != option else { return }
        currentOption = option
        defaults.set(option.rawValue, forKey: AppIconOption.storageKey)
    }

    private func commitExplicitSelection(_ option: AppIconOption) {
        commitIcon(option)
        // Keep the user's photo file; an explicit built-in choice should not stay hidden under it.
        if defaults.bool(forKey: PersonalBrandMarkStore.enabledKey) {
            defaults.set(false, forKey: PersonalBrandMarkStore.enabledKey)
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
