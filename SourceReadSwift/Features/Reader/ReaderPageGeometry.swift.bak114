import CoreGraphics
import Foundation
import SwiftUI

/// 章节标题在阅读页中的呈现方式。
///
/// 对标栖阅 / 开元阅读的阅读页：成熟产品把章节名放在页眉（12pt 灰色小字），
/// 正文从页眉下方固定位置开始，每一页都有页眉，而不是把 28pt 大标题塞进正文流。
/// 大标题模式保留给习惯旧版排版的用户。
enum ReaderPageChromeLayout: String, CaseIterable, Identifiable, Codable, Sendable {
    case header
    case inline
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .header: return "页眉小标题"
        case .inline: return "正文大标题"
        case .hidden: return "隐藏标题"
        }
    }

    var help: String {
        switch self {
        case .header:
            return "每页顶部一行 12pt 章节名，正文从页眉下方开始；与栖阅 / 开元阅读截图一致，页面利用率最高。"
        case .inline:
            return "章节第一页用大字号标题，标题占用正文高度；旧版排版。"
        case .hidden:
            return "不显示章节标题，正文直接从安全区下方开始。"
        }
    }
}

/// 阅读页几何常量。所有值都以 pt 为单位，来源是 390×844pt 竞品截图的像素量测：
/// 页眉墨迹 50–61、正文顶 84.3、正文底 819、页码底 831.7。
enum ReaderPageChrome {
    static let headerFontSize: CGFloat = 12
    static let footerFontSize: CGFloat = 11
    static let headerHeight: CGFloat = 15
    static let footerHeight: CGFloat = 14
    /// 页眉距安全区顶部 2pt：状态栏隐藏时页眉紧贴灵动岛下沿。
    static let headerTopGap: CGFloat = 2
    /// 页眉底到正文顶 17pt，合计正文顶 = safeTop + 34（竞品为 safeTop + 34.3）。
    static let headerToBodyGap: CGFloat = 17
    /// 滚动模式页眉行高（章节名 + 时间/电量一行）。分页页眉用 headerHeight，
    /// 滚动模式的页眉是浮层，行高固定 22pt，正文内边距与它共用同一常量。
    static let scrollHeaderBandHeight: CGFloat = 22
    /// 滚动模式底部状态带：20pt 文字 + 12pt 底部留白 + 8pt 与正文的间隙。
    /// 正文视口在页脚上方截止，不再从页脚下面穿过。
    static let scrollFooterBandHeight: CGFloat = 40

    /// 底部状态带是否启用：只有页脚位于底部时才需要占位。
    static func scrollFooterReservedHeight(statusPosition: String) -> CGFloat {
        (statusPosition == "bottom" || statusPosition == "both") ? scrollFooterBandHeight : 0
    }
    /// 页码离屏幕物理底 12pt（竞品 12.3pt）。
    static let footerBottomInset: CGFloat = 12
    static let minimumBodyHeight: CGFloat = 120
    static let bodyToFooterGap: CGFloat = 4
}

/// 单一几何来源：分页引擎、SwiftUI 页面、页眉页脚、页码都用这一份计算。
///
/// 旧实现里 `pageSurface` 叠加 `.padding(.top, safeTop + 4)`，分页引擎又用
/// `viewport.height - topPadding - bottomPadding - 4`，UIHostingController 还可能
/// 再应用一次安全区，三处各自扣一次，结果就是「顶部大片空白 + 页尾截断」。
struct ReaderPageGeometry: Equatable {
    let viewportSize: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let horizontalMargin: CGFloat
    let chromeLayout: ReaderPageChromeLayout
    let contentExtendsIntoChrome: Bool

    init(
        viewportSize: CGSize,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        horizontalMargin: CGFloat,
        chromeLayout: ReaderPageChromeLayout = .header,
        contentExtendsIntoChrome: Bool = false
    ) {
        let width = max(viewportSize.width, 1)
        let height = max(viewportSize.height, 1)
        self.viewportSize = CGSize(width: width, height: height)
        self.safeTop = max(safeTop, 0)
        self.safeBottom = max(safeBottom, 0)
        self.horizontalMargin = max(min(horizontalMargin, max((width - 80) * 0.5, 0)), 0)
        self.chromeLayout = chromeLayout
        self.contentExtendsIntoChrome = contentExtendsIntoChrome
    }

    var contentWidth: CGFloat {
        max(viewportSize.width - horizontalMargin * 2, 80)
    }

    var showsHeader: Bool { chromeLayout == .header }

    var headerTop: CGFloat { safeTop + ReaderPageChrome.headerTopGap }

    var headerRect: CGRect {
        CGRect(
            x: horizontalMargin,
            y: headerTop,
            width: contentWidth,
            height: ReaderPageChrome.headerHeight
        )
    }

    /// 页脚顶端。底部只让开 home indicator 的一半：既不会被手势条压住，
    /// 也不会像旧版那样把页码顶到屏幕中间。
    var footerTop: CGFloat {
        viewportSize.height
            - max(safeBottom * 0.5, ReaderPageChrome.footerBottomInset)
            - ReaderPageChrome.footerHeight
    }

    var footerRect: CGRect {
        CGRect(
            x: horizontalMargin,
            y: footerTop,
            width: contentWidth,
            height: ReaderPageChrome.footerHeight
        )
    }

    /// 正文起始 y。页眉模式固定 safeTop + 34，与竞品 84.3pt（safeTop 50）对齐。
    var bodyTop: CGFloat {
        if contentExtendsIntoChrome { return safeTop + 8 }
        switch chromeLayout {
        case .header:
            return safeTop + ReaderPageChrome.headerTopGap
                + ReaderPageChrome.headerHeight
                + ReaderPageChrome.headerToBodyGap
        case .inline:
            return safeTop + 8
        case .hidden:
            return safeTop + 12
        }
    }

    /// 正文结束 y。页脚上方留 4pt，竞品正文底 819 / 页码顶 821 的 2pt 间距。
    var bodyBottom: CGFloat {
        if contentExtendsIntoChrome { return viewportSize.height - 10 }
        return max(footerTop - ReaderPageChrome.bodyToFooterGap, bodyTop + 1)
    }

    var contentHeight: CGFloat {
        max(bodyBottom - bodyTop, ReaderPageChrome.minimumBodyHeight)
    }

    var bodyRect: CGRect {
        CGRect(
            x: horizontalMargin,
            y: bodyTop,
            width: contentWidth,
            height: contentHeight
        )
    }
}

/// 页面容器实测值。分页不能被「根视图尺寸」和「页面容器尺寸」的差异骗到：
/// UIHostingController 在 UIPageViewController 里可能被安全区再内缩一次。
/// 页面把真实尺寸与全局原点回传给分页引擎，两者从此使用同一组数字。
struct ReaderPageContainerMetrics: Equatable {
    var size: CGSize
    var globalMinY: CGFloat
    var rootViewportHeight: CGFloat
    var rootSafeTop: CGFloat
    var rootSafeBottom: CGFloat

    var isValid: Bool {
        size.width > 1 && size.height > 1 && rootViewportHeight > 1
    }

    /// 页面原点在屏幕顶部：安全区由页面自己补；原点已在安全区下方：页面内部不再补。
    var resolvedSafeTop: CGFloat {
        guard isValid else { return rootSafeTop }
        return globalMinY <= 1 ? rootSafeTop : 0
    }

    var resolvedSafeBottom: CGFloat {
        guard isValid else { return rootSafeBottom }
        return globalMinY + size.height >= rootViewportHeight - 1 ? rootSafeBottom : 0
    }

    func geometry(
        horizontalMargin: CGFloat,
        chromeLayout: ReaderPageChromeLayout,
        contentExtendsIntoChrome: Bool
    ) -> ReaderPageGeometry {
        ReaderPageGeometry(
            viewportSize: size,
            safeTop: resolvedSafeTop,
            safeBottom: resolvedSafeBottom,
            horizontalMargin: horizontalMargin,
            chromeLayout: chromeLayout,
            contentExtendsIntoChrome: contentExtendsIntoChrome
        )
    }
}

struct ReaderPageContainerMetricsKey: PreferenceKey {
    static var defaultValue: ReaderPageContainerMetrics?

    static func reduce(value: inout ReaderPageContainerMetrics?, nextValue: () -> ReaderPageContainerMetrics?) {
        if let next = nextValue(), next.isValid {
            value = next
        }
    }
}
