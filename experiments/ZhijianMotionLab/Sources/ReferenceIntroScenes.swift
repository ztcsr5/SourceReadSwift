import SwiftUI

/// Rebuilt geometry from the user's video; no extracted executable is used.
struct ReferencePosterField: View {
    let step: Int
    let isAnimated: Bool
    var sampledTime: Double?
    @State private var origin = Date()
    private let ids = [157336, 82728, 496243, 508943, 87739, 560057, 475557, 603, 240, 60573, 12971, 823219, 10997, 10376, 110356]

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimated || sampledTime != nil)) { context in
                let time = sampledTime ?? (isAnimated ? context.date.timeIntervalSince(origin) : 0)
                let width = proxy.size.width
                ZStack {
                    ForEach(ids.indices, id: \.self) { index in
                        let pose = pose(index, time: time, size: proxy.size)
                        VStack(spacing: 5) {
                            ReferencePoster(item: ReferenceMedia.item(ids[index]), radius: step == 1 && index < 3 ? 12 : 6)
                                .frame(width: pose.width, height: pose.width * 1.5)
                                .shadow(color: .black.opacity(step == 0 ? 0.25 : 0.04), radius: step == 0 ? 7 : 2, y: 5)
                            if step == 1 && index < 3 {
                                Text(ReferenceMedia.item(ids[index]).title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(ReferenceMedia.item(ids[index]).year).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                        .scaleEffect(pose.scale).blur(radius: pose.blur).opacity(pose.opacity)
                        .position(x: pose.x, y: pose.y)
                        .zIndex(step == 0 ? Double(index % 3) : 0)
                    }
                    if step == 0 {
                        ReferenceMark().fill(.black).frame(width: width * 0.24, height: width * 0.24)
                            .position(x: width * 0.50, y: proxy.size.height * 0.49)
                            .transition(.opacity.combined(with: .scale))
                    }
                    if step == 1 {
                        previewModules(width: width)
                            .offset(y: proxy.size.height * 0.74 - min(max(time - 1.7, 0) * 32, 220))
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    }
                }
                .animation(isAnimated ? .spring(response: 0.75, dampingFraction: 0.9) : nil, value: step)
            }
        }
        .onChange(of: step) { _ in origin = Date() }
        .clipped().accessibilityHidden(true).allowsHitTesting(false)
    }

    private struct Pose {
        let x: CGFloat; let y: CGFloat; let width: CGFloat
        let scale: CGFloat; let blur: CGFloat; let opacity: Double
    }

    private func pose(_ index: Int, time: Double, size: CGSize) -> Pose {
        let width = size.width
        if step == 1 {
            let firstRow = index < 3
            let row = firstRow ? 0 : (index - 3) / 4 + 1
            let column = firstRow ? index : (index - 3) % 4
            let cover = width * (firstRow ? 0.266 : 0.182)
            let x = firstRow ? width * 0.167 + CGFloat(column) * width * 0.30 : width * 0.137 + CGFloat(column) * width * 0.244
            let scroll = min(max(time - 1.7, 0) * 32, 220)
            let y = firstRow ? width * 0.255 : width * 0.65 + CGFloat(row - 1) * width * 0.31
            return Pose(x: x, y: y - scroll, width: cover, scale: 1, blur: 0, opacity: 1)
        }
        let columns: [CGFloat] = [0.72, 0.20, 0.42, 0.90, 0.54, 0.12, 0.83, 0.69, 0.32, 0.88, 0.07, 0.09, 0.54, 0.24, 0.62]
        let rows: [CGFloat] = [0.65, 0.35, 0.12, 0.24, 0.16, 0.68, 0.40, 0.82, 0.79, 0.73, 0.22, 0.44, 0.86, 0.58, 0.49]
        let back = index % 3 == 1
        let drift = sin(time * 0.30 + Double(index) * 0.72) * Double(size.height * 0.045)
        return Pose(x: columns[index] * width + CGFloat(cos(time * 0.12 + Double(index)) * 3),
                    y: rows[index] * size.height + CGFloat(drift), width: width * 0.18,
                    scale: back ? 0.80 : 1, blur: back ? 4 : 0, opacity: back ? 0.55 : 1)
    }

    private func previewModules(width: CGFloat) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ReferenceImage(name: ReferenceMedia.item(277834).backdrop).frame(width: width * 0.42, height: width * 0.24).clipShape(RoundedRectangle(cornerRadius: 14))
                ReferenceImage(name: ReferenceMedia.item(560057).backdrop).frame(width: width * 0.42, height: width * 0.24).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            VStack(spacing: 14) {
                Text("‹   我的片单   ›").font(.headline)
                HStack(spacing: -10) {
                    ForEach([46298, 12971, 799876, 238], id: \.self) { id in
                        ReferencePoster(item: ReferenceMedia.item(id)).frame(width: width * 0.13, height: width * 0.15).rotationEffect(.degrees(Double(id % 7 - 3)))
                    }
                }
                Text("1   全职猎人\n2   犬夜叉\n3   套装").font(.caption).lineSpacing(6)
            }.frame(width: width * 0.68).padding(20).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        }.frame(width: width)
    }
}

struct ReferenceMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.width * 0.43, y: rect.height * 0.55)
        let radius = rect.width * 0.42
        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: center.x, y: rect.height * 0.35))
        path.addArc(center: center, radius: radius * 0.49, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: true)
        path.closeSubpath()
        let x = rect.width * 0.72, y = rect.height * 0.25, r = rect.width * 0.25
        path.move(to: CGPoint(x: x, y: y - r))
        path.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
        path.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x, y: y))
        path.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x, y: y))
        path.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x, y: y))
        path.closeSubpath()
        return path
    }
}

struct ReferenceOrbit: View {
    let isAnimated: Bool
    var sampledTime: Double?
    @State private var origin = Date()
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimated || sampledTime != nil)) { context in
                let time = sampledTime ?? (isAnimated ? context.date.timeIntervalSince(origin) : 0)
                ZStack {
                    ReferencePoster(item: ReferenceMedia.item(106379), radius: 13)
                        .frame(width: proxy.size.width * 0.29, height: proxy.size.width * 0.435).zIndex(0)
                    ForEach(0..<4, id: \.self) { index in
                        let angle = time * 0.38 + Double(index) * .pi / 2 - 2.2
                        let depth = sin(angle)
                        icon(index).scaleEffect(0.92 + depth * 0.12)
                            .offset(x: cos(angle) * Double(proxy.size.width * 0.32), y: sin(angle) * Double(proxy.size.width * 0.29))
                            .zIndex(depth > 0 ? 1 : -1)
                    }
                }.frame(width: proxy.size.width, height: proxy.size.height)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
    @ViewBuilder private func icon(_ index: Int) -> some View {
        if index == 0 {
            Image(systemName: "folder.fill").font(.system(size: 48)).foregroundStyle(.blue.gradient).shadow(color: .blue.opacity(0.25), radius: 8, y: 4)
        } else if index == 1 {
            Image(systemName: "play.fill").font(.system(size: 27)).foregroundStyle(.white)
                .frame(width: 47, height: 47).background(.green, in: RoundedRectangle(cornerRadius: 5)).rotationEffect(.degrees(45))
        } else if index == 2 {
            Text("plex").font(.system(size: 25, weight: .bold)).foregroundStyle(.white)
                .frame(width: 57, height: 57).background(.black, in: Circle())
        } else {
            Image(systemName: "triangle").font(.system(size: 43, weight: .bold)).foregroundStyle(.purple.gradient)
        }
    }
}
