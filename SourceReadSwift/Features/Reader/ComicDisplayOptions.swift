import UIKit

enum ComicCanvas: String, CaseIterable, Identifiable {
    case black = "黑色"
    case white = "白色"
    case system = "跟随系统"

    var id: String { rawValue }
    var color: UIColor {
        switch self {
        case .black: return .black
        case .white: return .white
        case .system: return .systemBackground
        }
    }
    var ink: UIColor {
        switch self {
        case .black: return .white
        case .white: return .black
        case .system: return .label
        }
    }
}

enum ComicStripMarginDirection: String, CaseIterable, Identifiable {
    case both = "全部"
    case portrait = "竖屏"
    case landscape = "横屏"

    var id: String { rawValue }

    func allowsMargin(size: CGSize) -> Bool {
        switch self {
        case .both: return true
        case .portrait: return size.height >= size.width
        case .landscape: return size.width > size.height
        }
    }
}

struct ComicDisplayOptions: Equatable {
    static let maximumPrefetchPages = 5
    static let defaultPrefetchPages = 3
    static let prefetchPageRange = 0...maximumPrefetchPages
    static let marginRange = 0...40

    var canvas: ComicCanvas = .black
    var preloadPages = defaultPrefetchPages
    var reducesImageQuality = false
    var disablesDoubleTap = false
    var showsStripMargins = false
    var stripMarginPercent = 15
    var stripMarginDirection: ComicStripMarginDirection = .both

    var maxImagePixels: CGFloat { reducesImageQuality ? 2048 : ComicPagePositionPolicy.maxImagePixels }

    func artworkRatio(viewport: CGSize) -> CGFloat {
        guard showsStripMargins, stripMarginDirection.allowsMargin(size: viewport) else { return 1 }
        let percent = min(max(stripMarginPercent, Self.marginRange.lowerBound), Self.marginRange.upperBound)
        return 1 - CGFloat(percent) / 100
    }
}
