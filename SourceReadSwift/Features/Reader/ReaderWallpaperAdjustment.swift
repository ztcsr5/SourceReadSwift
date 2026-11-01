import Foundation
import CoreGraphics

struct ReaderWallpaperAdjustment: Codable, Equatable, Sendable {
    var zoom = 1.0
    var horizontalOffset = 0.0
    var verticalOffset = 0.0
    var dimming = 0.0
    var usesLightText = false
    var fillMode = ReaderWallpaperFillMode.fill

    func validate() throws {
        guard zoom.isFinite, (1...3).contains(zoom), horizontalOffset.isFinite, (-1...1).contains(horizontalOffset),
              verticalOffset.isFinite, (-1...1).contains(verticalOffset), dimming.isFinite, (0...0.6).contains(dimming) else {
            throw ReaderWallpaperFailure.invalidAdjustment
        }
    }

    func imageFrame(imageSize: CGSize, viewport: CGSize, mode: ReaderWallpaperFillMode) -> CGRect {
        guard imageSize.width.isFinite, imageSize.height.isFinite, viewport.width.isFinite, viewport.height.isFinite,
              imageSize.width > 0, imageSize.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let ratio = mode == .fit ? min(viewport.width / imageSize.width, viewport.height / imageSize.height) :
            max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let base = mode == .stretch ? viewport : CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
        let scale = CGFloat(zoom.isFinite ? min(max(zoom, 1), 3) : 1)
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        let x = horizontalOffset.isFinite ? min(max(horizontalOffset, -1), 1) : 0
        let y = verticalOffset.isFinite ? min(max(verticalOffset, -1), 1) : 0
        return CGRect(x: (viewport.width - size.width) / 2 + CGFloat(x) * max(size.width - viewport.width, 0) / 2,
                      y: (viewport.height - size.height) / 2 + CGFloat(y) * max(size.height - viewport.height, 0) / 2,
                      width: size.width, height: size.height)
    }
}

enum ReaderWallpaperFailure: LocalizedError {
    case invalidImage, tooLarge, invalidAdjustment, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法解码壁纸，请重新选择 JPEG、PNG 或 HEIC 图片。"
        case .tooLarge: return "壁纸超过大小限制，请选择不超过 20 MB 的图片。"
        case .invalidAdjustment: return "壁纸编辑参数无效，请重置裁切后重试。"
        case .unsupportedVersion: return "壁纸文件版本不受支持，原文件未被修改。"
        }
    }
}
