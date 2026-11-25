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

enum ComicChromeStyle: String, CaseIterable, Identifiable {
    case capsule = "capsule"
    case minimal = "minimal"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .capsule: return "悬浮胶囊"
        case .minimal: return "极简通栏"
        }
    }
}

enum ComicChromeSlotContent: String, CaseIterable, Identifiable {
    case none = "none"
    case chapterTitle = "chapterTitle"
    case bookTitle = "bookTitle"
    case pageProgress = "pageProgress"
    case percent = "percent"
    case chapterAndPage = "chapterAndPage"
    case time = "time"
    case battery = "battery"
    case timeAndBattery = "timeAndBattery"
    case pageAndBattery = "pageAndBattery"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "留空"
        case .chapterTitle: return "话名"
        case .bookTitle: return "漫画名"
        case .pageProgress: return "页码 (1/42 P)"
        case .percent: return "进度百分比"
        case .chapterAndPage: return "话名 + 页码"
        case .time: return "当前时间"
        case .battery: return "当前电量"
        case .timeAndBattery: return "时间 + 电量"
        case .pageAndBattery: return "页码 + 电量"
        }
    }
}

struct ComicDisplayOptions: Equatable {
    static let maximumPrefetchPages = 12
    static let defaultPrefetchPages = 6
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
