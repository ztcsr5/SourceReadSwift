import SwiftUI
import UIKit

enum ReaderChapterAlignment: String, CaseIterable, Codable, Sendable {
    case leading, center, trailing
    var title: String { self == .leading ? "居左" : self == .center ? "居中" : "居右" }
    var textAlignment: NSTextAlignment { self == .leading ? .natural : self == .center ? .center : .right }
    var swiftUI: TextAlignment { self == .leading ? .leading : self == .center ? .center : .trailing }
    var css: String { self == .leading ? "left" : self == .center ? "center" : "right" }
}

/// Original print ornaments share the same vector strokes in WebKit, TextKit and previews.
enum ReaderChapterDecoration: String, CaseIterable, Codable, Sendable {
    case none, folio, mountains, branch, constellation
    var title: String {
        switch self { case .none: return "素笺"; case .folio: return "藏书印记"; case .mountains: return "山岚入卷"
        case .branch: return "枝影留白"; case .constellation: return "星河来信" }
    }
    var height: CGFloat { self == .none ? 0 : 40 }
    var prefixLength: Int { self == .none ? 0 : 2 }
    var strokes: [[CGPoint]] {
        let lines: [[Double]]
        switch self {
        case .none: lines = []
        case .folio: lines = [[12,20,62,20],[98,20,148,20],[80,8,92,20,80,32,68,20,80,8],[77,20,83,20]]
        case .mountains: lines = [[8,32,40,9,57,24,77,4,108,32],[69,32,108,13,151,32],[32,31,41,22,46,27],[15,36,145,36]]
        case .branch: lines = [[19,31,48,26,76,18,105,13,140,9],[48,26,40,14,54,18,58,23],[76,18,70,6,86,12,85,16],[98,14,113,25,96,23,90,17],[119,11,132,2,134,10]]
        case .constellation: lines = [[19,29,49,11,83,23,117,8,143,24],[46,11,52,11],[49,8,49,14],[80,23,86,23],[83,20,83,26],[113,8,121,8],[117,4,117,12],[140,24,146,24],[143,21,143,27]]
        }
        return lines.map { line in stride(from: 0, to: line.count, by: 2).map { CGPoint(x: line[$0], y: line[$0 + 1]) } }
    }
    func svg(ink: String) -> String {
        let paths = strokes.map { points in
            "<polyline points='" + points.map { "\($0.x),\($0.y)" }.joined(separator: " ") + "'/>"
        }.joined()
        return "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 160 40'><g fill='none' stroke='\(ink)' stroke-opacity='.65' stroke-width='1.3' stroke-linecap='round' stroke-linejoin='round'>\(paths)</g></svg>"
    }
    func cssImage(ink: UIColor) -> String {
        guard self != .none else { return "none" }
        return "url(\"data:image/svg+xml;base64,\(Data(svg(ink: WebReaderColor.hex(ink)).utf8).base64EncodedString())\")"
    }
    private static let cache = NSCache<NSString, UIImage>()
    func image(ink: UIColor) -> UIImage {
        let key = (rawValue + WebReaderColor.hex(ink)) as NSString
        if let image = Self.cache.object(forKey: key) { return image }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 40), format: format).image { renderer in
            let context = renderer.cgContext; context.setStrokeColor(ink.withAlphaComponent(0.65).cgColor)
            context.setLineWidth(1.3); context.setLineCap(.round); context.setLineJoin(.round)
            for points in strokes {
                guard let first = points.first else { continue }
                context.beginPath(); context.move(to: first)
                for point in points.dropFirst() { context.addLine(to: point) }
                context.strokePath()
            }
        }
        Self.cache.countLimit = 40; Self.cache.totalCostLimit = 4 * 1024 * 1024
        Self.cache.setObject(image, forKey: key, cost: 160 * 40 * 16)
        return image
    }
}

struct ReaderChapterMotif: View {
    let decoration: ReaderChapterDecoration
    var width: CGFloat = 160
    var body: some View {
        Canvas { context, size in
            for points in decoration.strokes {
                var path = Path()
                for (index, point) in points.enumerated() {
                    let scaled = CGPoint(x: point.x / 160 * size.width, y: point.y / 40 * size.height)
                    if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
                }
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
        }.frame(width: width, height: decoration.height).opacity(0.65).accessibilityHidden(true)
    }
}
