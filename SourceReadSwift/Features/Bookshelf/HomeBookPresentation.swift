import Foundation

/// Book-only home arrangements, independent of the selected color theme.
enum HomeBookPresentation: String, CaseIterable, Identifiable {
    case current, showcase, journal, classic, sculptural, magazine, library

    /// Retired IDs remain decodable for existing preferences and backups, never as menu options.
    static let allCases: [Self] = [.showcase, .journal, .classic]

    static let storageKey = "settings.homeBookPresentation"
    static let initialSelection: Self = .showcase
    var id: String { rawValue }
    var usesClassicDesk: Bool { self == .classic || self == .current }

    static func bootstrapSelection(in defaults: UserDefaults, isExistingInstall: Bool) {
        guard defaults.object(forKey: storageKey) == nil else { return }
        defaults.set((isExistingInstall ? Self.classic : Self.showcase).rawValue, forKey: storageKey)
    }

    var title: String {
        switch self {
        case .current: return "现有书桌"
        case .showcase: return "展台"
        case .journal: return "手账"
        case .classic: return "经典"
        case .sculptural: return "拟物"
        case .magazine: return "杂志"
        case .library: return "图书馆"
        }
    }

    var symbol: String {
        switch self {
        case .current: return "rectangle.on.rectangle"
        case .showcase: return "rectangle.center.inset.filled"
        case .journal: return "rectangle.topthird.inset.filled"
        case .classic: return "rectangle.leadinghalf.inset.filled"
        case .sculptural: return "book.closed"
        case .magazine: return "books.vertical"
        case .library: return "books.vertical.fill"
        }
    }

    static func resolve(_ rawValue: String) -> Self {
        switch Self(rawValue: rawValue) ?? .classic {
        case .sculptural, .magazine, .library: return .classic
        case let presentation: return presentation
        }
    }
}
