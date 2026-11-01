import UIKit

/// Original low-contrast line drawings; no remote assets or per-frame animation.
enum ReaderDoodlePattern: CaseIterable {
    case cats, letters, clouds, planes

    func draw(in context: CGContext, ink: UIColor, night: Bool) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(ink.withAlphaComponent(night ? 0.09 : 0.075).cgColor)
        context.setLineWidth(1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for origin in [CGPoint(x: 18, y: 28), CGPoint(x: 178, y: 176)] {
            context.saveGState()
            context.translateBy(x: origin.x, y: origin.y)
            switch self {
            case .cats: drawCat(context)
            case .letters: drawLetter(context)
            case .clouds: drawCloud(context)
            case .planes: drawPlane(context)
            }
            context.restoreGState()
        }
    }

    private func drawCat(_ context: CGContext) {
        context.move(to: CGPoint(x: 2, y: 19))
        context.addLine(to: CGPoint(x: 1, y: 2)); context.addLine(to: CGPoint(x: 10, y: 7))
        context.addQuadCurve(to: CGPoint(x: 22, y: 7), control: CGPoint(x: 16, y: 4))
        context.addLine(to: CGPoint(x: 31, y: 2)); context.addLine(to: CGPoint(x: 30, y: 19))
        context.addCurve(to: CGPoint(x: 2, y: 19), control1: CGPoint(x: 28, y: 29), control2: CGPoint(x: 4, y: 29))
        context.move(to: CGPoint(x: 10, y: 14)); context.addLine(to: CGPoint(x: 11, y: 16))
        context.move(to: CGPoint(x: 21, y: 14)); context.addLine(to: CGPoint(x: 22, y: 16))
        context.move(to: CGPoint(x: 14, y: 20)); context.addQuadCurve(to: CGPoint(x: 18, y: 20), control: CGPoint(x: 16, y: 23))
        context.move(to: CGPoint(x: 0, y: 17)); context.addLine(to: CGPoint(x: 6, y: 18))
        context.move(to: CGPoint(x: 26, y: 18)); context.addLine(to: CGPoint(x: 34, y: 17))
        context.strokePath()
    }

    private func drawLetter(_ context: CGContext) {
        context.stroke(CGRect(x: 0, y: 12, width: 32, height: 21))
        context.move(to: CGPoint(x: 0, y: 12)); context.addLine(to: CGPoint(x: 16, y: 24)); context.addLine(to: CGPoint(x: 32, y: 12))
        context.move(to: CGPoint(x: 0, y: 33)); context.addLine(to: CGPoint(x: 11, y: 23))
        context.move(to: CGPoint(x: 32, y: 33)); context.addLine(to: CGPoint(x: 22, y: 23))
        context.move(to: CGPoint(x: 27, y: 0))
        context.addCurve(to: CGPoint(x: 36, y: 9), control1: CGPoint(x: 20, y: 9), control2: CGPoint(x: 27, y: 15))
        context.addQuadCurve(to: CGPoint(x: 27, y: 0), control: CGPoint(x: 26, y: 12))
        context.strokePath()
    }

    private func drawCloud(_ context: CGContext) {
        context.move(to: CGPoint(x: 5, y: 20))
        context.addCurve(to: CGPoint(x: 9, y: 7), control1: CGPoint(x: -5, y: 20), control2: CGPoint(x: -3, y: 7))
        context.addCurve(to: CGPoint(x: 25, y: 7), control1: CGPoint(x: 10, y: -3), control2: CGPoint(x: 23, y: -3))
        context.addCurve(to: CGPoint(x: 32, y: 20), control1: CGPoint(x: 39, y: 3), control2: CGPoint(x: 44, y: 20))
        context.addLine(to: CGPoint(x: 5, y: 20))
        context.move(to: CGPoint(x: 8, y: 27)); context.addQuadCurve(to: CGPoint(x: 30, y: 27), control: CGPoint(x: 19, y: 33))
        context.move(to: CGPoint(x: 14, y: 36)); context.addLine(to: CGPoint(x: 25, y: 36))
        context.strokePath()
    }

    private func drawPlane(_ context: CGContext) {
        context.move(to: CGPoint(x: 0, y: 15)); context.addLine(to: CGPoint(x: 37, y: 0))
        context.addLine(to: CGPoint(x: 26, y: 32)); context.addLine(to: CGPoint(x: 16, y: 22)); context.closePath()
        context.move(to: CGPoint(x: 16, y: 22)); context.addLine(to: CGPoint(x: 37, y: 0))
        context.move(to: CGPoint(x: 16, y: 22)); context.addLine(to: CGPoint(x: 13, y: 30)); context.addLine(to: CGPoint(x: 22, y: 26))
        context.move(to: CGPoint(x: 1, y: 30)); context.addLine(to: CGPoint(x: 1, y: 38))
        context.move(to: CGPoint(x: -3, y: 34)); context.addLine(to: CGPoint(x: 5, y: 34))
        context.strokePath()
    }
}
