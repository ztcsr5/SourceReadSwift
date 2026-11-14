import SwiftUI
import UIKit

/// 壁纸填充方式。对齐开元（Flutter `BoxFit`）与栖阅（UIImageView contentMode）：
/// 填充裁切 / 完整显示 / 拉伸铺满。
enum ReaderWallpaperFillMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
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
    var adjustment = ReaderWallpaperAdjustment()
    var isNight = false

    func makeUIView(context: Context) -> ReaderWallpaperUIImageView {
        let view = ReaderWallpaperUIImageView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        view.configure(image: image, fillMode: fillMode, adjustment: adjustment, isNight: isNight)
        return view
    }

    func updateUIView(_ view: ReaderWallpaperUIImageView, context: Context) {
        view.configure(image: image, fillMode: fillMode, adjustment: adjustment, isNight: isNight)
    }
}

private enum ReaderWallpaperBlurCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 4
        return cache
    }()
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func image(for source: UIImage, radius: Double) -> UIImage {
        let quantized = Int((min(max(radius.isFinite ? radius : 0, 0), 24) * 2).rounded())
        guard quantized > 0 else { return source }
        let key = "\(ObjectIdentifier(source).hashValue)|\(quantized)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let ciInput = CIImage(image: source),
              let filter = CIFilter(name: "CIGaussianBlur") else { return source }
        filter.setValue(ciInput.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(Double(quantized) * 0.5, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage,
              let cg = ciContext.createCGImage(output, from: ciInput.extent) else { return source }
        let blurred = UIImage(cgImage: cg, scale: source.scale, orientation: source.imageOrientation)
        cache.setObject(blurred, forKey: key)
        return blurred
    }
}

final class ReaderWallpaperUIImageView: UIView {
    private let picture = UIImageView()
    private let grain = UIImageView()
    private let shade = UIView()
    private var sourceImage: UIImage?
    private var fillMode: ReaderWallpaperFillMode = .fill
    private var adjustment = ReaderWallpaperAdjustment()
    private var isNight = false
    private var lastAppliedBlurBucket = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        picture.contentMode = .scaleToFill
        grain.contentMode = .scaleToFill
        addSubview(picture); addSubview(grain); addSubview(shade)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(image: UIImage, fillMode: ReaderWallpaperFillMode, adjustment: ReaderWallpaperAdjustment, isNight: Bool) {
        let bucket = Int((min(max(adjustment.blurRadius, 0), 24) * 2).rounded())
        let imageChanged = sourceImage !== image || bucket != lastAppliedBlurBucket
        self.sourceImage = image
        self.fillMode = fillMode
        self.adjustment = adjustment
        self.isNight = isNight
        if imageChanged {
            lastAppliedBlurBucket = bucket
            picture.image = ReaderWallpaperBlurCache.image(for: image, radius: adjustment.blurRadius)
        }
        if adjustment.grainOpacity > 0.005 {
            grain.isHidden = false
            grain.image = ReaderPaperTexture.image(background: .linen, night: isNight)
            grain.alpha = CGFloat(min(max(adjustment.grainOpacity, 0), 0.35))
        } else {
            grain.isHidden = true
            grain.image = nil
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picture.frame = adjustment.imageFrame(imageSize: sourceImage?.size ?? .zero, viewport: bounds.size, mode: fillMode)
        grain.frame = bounds
        shade.frame = bounds
        let dim = isNight ? adjustment.nightDimming : adjustment.dimming
        shade.backgroundColor = UIColor.black.withAlphaComponent(dim.isFinite ? min(max(dim, 0), 0.85) : 0)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

/// 壁纸导入与布局的纯计算部分，方便单元测试。
enum ReaderWallpaperLayoutPolicy {
    /// Preserve the reader's aspect ratio; a wide editor row would otherwise preview a different crop.
    static func previewSize(viewport: CGSize, available: CGSize) -> CGSize {
        guard viewport.width.isFinite, viewport.height.isFinite, available.width.isFinite, available.height.isFinite,
              viewport.width > 0, viewport.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / viewport.width, available.height / viewport.height)
        return CGSize(width: viewport.width * scale, height: viewport.height * scale)
    }

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
