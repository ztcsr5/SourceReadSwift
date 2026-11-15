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
        case .ink: return "雾纸"
        case .jianghu: return "断锋"
        case .sky: return "晴空"
        case .journal: return "兔兔"
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
        case .ink: return "一叶轻舟入雾。宣白、烟墨与收锋细线。"
        case .jianghu: return "风从崖侧起。飞白、切角与一线锋芒。"
        case .sky: return "风从檐边经过，天色晚得很慢。"
        case .journal: return "把莓果夹进书页。兔耳、圆签与小小爪印。"
        }
    }
}
