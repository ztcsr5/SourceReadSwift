import SwiftUI

/// The four illustrated editions share a gallery, not a common color treatment.
enum AtmosphericThemeSignature: String {
    case ink, jianghu, sky, journal

    init?(theme: AppVisualTheme) {
        switch theme {
        case .shuimo: self = .ink
        case .wuxia: self = .jianghu
        case .anime: self = .sky
        case .kawaii: self = .journal
        default: return nil
        }
    }

    var shortTitle: String {
        switch self {
        case .ink: return "墨山"
        case .jianghu: return "竹雨"
        case .sky: return "晴空"
        case .journal: return "花信"
        }
    }

    var catalogueNumber: String {
        switch self {
        case .ink: return "01"
        case .jianghu: return "02"
        case .sky: return "03"
        case .journal: return "04"
        }
    }

    var caption: String {
        switch self {
        case .ink: return "松烟沿山脊漫开，留一方朱印。"
        case .jianghu: return "穿过竹林，听雨落在旧石阶上。"
        case .sky: return "风从檐边经过，天色晚得很慢。"
        case .journal: return "把春天夹进一张折了角的信纸。"
        }
    }
}
