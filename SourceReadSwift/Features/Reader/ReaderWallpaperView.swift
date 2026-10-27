import SwiftUI
import UIKit

/// 壁纸填充方式。对齐开元（Flutter `BoxFit`）与栖阅（UIImageView contentMode）：
/// 填充裁切 / 完整显示 / 拉伸铺满。
enum ReaderWallpaperFillMode: String, CaseIterable, Identifiable {
    case fill
    case fit
    case stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "填充"
        case .fit: return "适应"
        case .stretch: return "拉伸"
        }
    }

    var uiContentMode: UIView.ContentMode {
        switch self {
        case .fill: return .scaleAspectFill
        case .fit: return .scaleAspectFit
        case .stretch: return .scaleToFill
        }
    }
}

/// 用 UIKit 的 `UIImageView` 承载阅读壁纸。
///
/// SwiftUI 的 `Image.resizable().scaledToFill()` 会把“按比例填充后的尺寸”
/// 报告给父级 ZStack。只要图片比例和屏幕不一致，根布局就可能被撑宽，
/// 设置面板与工具条随之左右溢出。`UIImageView` 的 `intrinsicContentSize`
/// 是 `noIntrinsicMetric`，布局完全由 SwiftUI 提案决定，从根上切断这条路径。
///
/// 参考栖阅的 `staticBackgroundImageView`：背景固定、正文滚动、壁纸层不参与
/// 文本排版。
struct ReaderWallpaperView: UIViewRepresentable {
    let image: UIImage
    let fillMode: ReaderWallpaperFillMode

    func makeUIView(context: Context) -> ReaderWallpaperUIImageView {
        let view = ReaderWallpaperUIImageView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        view.image = image
        view.fillMode = fillMode
        return view
    }

    func updateUIView(_ view: ReaderWallpaperUIImageView, context: Context) {
        view.image = image
        view.fillMode = fillMode
    }
}

final class ReaderWallpaperUIImageView: UIImageView {
    var fillMode: ReaderWallpaperFillMode = .fill {
        didSet {
            contentMode = fillMode.uiContentMode
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

/// 壁纸导入与布局的纯计算部分，方便单元测试。
enum ReaderWallpaperLayoutPolicy {
    /// 3x 屏最高约 2796px；2800 足够全屏清晰，又不会让解码后的位图过大。
    static let maxPixelDimension: CGFloat = 2800

    /// 按最长边等比缩放；小于上限时保持原尺寸（不放大）。
    static func downsampledPixelSize(
        for size: CGSize,
        maxPixel: CGFloat = 2800
    ) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > maxPixel, longest > 0, maxPixel > 0 else { return size }
        let ratio = maxPixel / longest
        return CGSize(
            width: max((size.width * ratio).rounded(), 1),
            height: max((size.height * ratio).rounded(), 1)
        )
    }

    /// 导入时先降采样再存盘，避免相册原图（常见 12MP）长期占用大量内存。
    static func downsampledImage(
        _ image: UIImage,
        maxPixel: CGFloat = maxPixelDimension
    ) -> UIImage {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let target = downsampledPixelSize(for: pixelSize, maxPixel: maxPixel)
        guard target != pixelSize else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
