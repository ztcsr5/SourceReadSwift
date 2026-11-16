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
        case .ink: return "黑白宣纸 · 苍松远岫、孤舟游轨与方章印框。"
        case .jianghu: return "黑白飞白 · 剑风破竹、八角墨签与菱形剑锷滑块。"
        case .sky: return "风从檐边经过，星芒刻度与晴空明晰交互。"
        case .journal: return "草莓奶油 · 蕾丝云床、跳动兔耳滑块与手账缝边。"
        }
    }
}
