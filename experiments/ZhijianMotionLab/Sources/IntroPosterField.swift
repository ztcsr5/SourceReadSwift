import SwiftUI

/// Per-frame updates stay inside this decorative leaf, never the app or reader tree.
struct IntroPosterField: View {
    let step: Int
    let isAnimated: Bool
    var sampledTime: Double? = nil
    @State private var origin = Date()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimated || sampledTime != nil)) { timeline in
                let time = sampledTime ?? (isAnimated ? timeline.date.timeIntervalSince(origin) : 0)
                let size = proxy.size
                ZStack {
                    ForEach(0..<12, id: \.self) { index in
                        let book = LabBook.samples[index % LabBook.samples.count]
                        let pose = pose(index: index, time: time, size: size)
                        LabCover(book: book, radius: 8)
                            .frame(width: pose.width, height: pose.width * 1.42)
                            .rotation3DEffect(.degrees(pose.tilt), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                            .rotationEffect(.degrees(pose.rotation))
                            .scaleEffect(pose.scale)
                            .opacity(pose.opacity)
                            .blur(radius: step == 0 && index % 3 == 0 ? 2 : 0)
                            .shadow(color: .black.opacity(0.16), radius: 9, x: 0, y: 7)
                            .position(x: size.width * 0.5 + pose.x, y: size.height * 0.5 + pose.y)
                            .zIndex(pose.depth)
                    }
                    if step == 0 {
                        LabMark().foregroundStyle(LabPalette.ink)
                            .background(Circle().fill(LabPalette.paper.opacity(0.8)).frame(width: 110, height: 110))
                            .position(x: size.width / 2, y: size.height / 2)
                            .transition(.scale.combined(with: .opacity))
                    }
                    if step == 1 {
                        VStack(spacing: 5) {
                            Text("私人藏书室").font(.system(.title2, design: .serif).weight(.semibold))
                            Text("小说 / 图文 / 本地 · 都有自己的位置")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .position(x: size.width / 2, y: size.height * 0.91)
                        .transition(.opacity)
                    }
                }
                .animation(isAnimated ? LabPalette.navigation : nil, value: step)
            }
        }
        .accessibilityHidden(true).allowsHitTesting(false)
    }

    private struct Pose {
        var x: CGFloat; var y: CGFloat; var width: CGFloat; var scale: CGFloat
        var rotation: Double; var tilt: Double; var opacity: Double; var depth: Double
    }

    private func pose(index: Int, time: Double, size: CGSize) -> Pose {
        if step == 1 {
            let column = index % 4, row = index / 4
            let gap = min(size.width * 0.225, 94)
            return Pose(x: CGFloat(column) * gap - gap * 1.5, y: CGFloat(row - 1) * gap * 1.47 - 20,
                        width: gap * 0.78, scale: 1, rotation: 0, tilt: 0, opacity: 1, depth: Double(index))
        }
        let columns: [CGFloat] = [-0.36, 0.32, -0.13, 0.14, -0.40, 0.40, -0.26, 0.29, -0.08, 0.1, -0.43, 0.45]
        let rows: [CGFloat] = [-0.32, -0.28, -0.52, 0.38, 0.05, -0.02, 0.39, 0.25, 0.60, -0.60, -0.52, 0.53]
        let phase = Double(index) * 0.86
        let drift = sin(time * 0.38 + phase) * 16
        let depth = index % 3
        return Pose(x: columns[index] * size.width + CGFloat(cos(time * 0.17 + phase) * 5),
                    y: rows[index] * size.height + CGFloat(drift), width: min(size.width * 0.215, 86),
                    scale: depth == 0 ? 0.72 : (depth == 1 ? 0.9 : 1.06),
                    rotation: Double(index % 2 == 0 ? -6 : 7), tilt: Double(index % 2 == 0 ? -10 : 10),
                    opacity: depth == 0 ? 0.48 : 1, depth: Double(depth))
    }
}

struct IntroOrbit: View {
    let isAnimated: Bool
    var sampledTime: Double? = nil
    @State private var origin = Date()
    private let symbols = ["doc.text", "books.vertical", "headphones", "text.book.closed", "network"]
    private let labels = ["TXT", "EPUB", "有声", "图文", "书源"]

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimated || sampledTime != nil)) { timeline in
                let time = sampledTime ?? (isAnimated ? timeline.date.timeIntervalSince(origin) : 0)
                ZStack {
                    Ellipse().stroke(LabPalette.accent.opacity(0.13), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                        .frame(width: proxy.size.width * 0.91, height: 148).rotationEffect(.degrees(-18))
                    LabCover(book: LabBook.samples[0]).frame(width: 126, height: 184)
                        .rotation3DEffect(.degrees(-7), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .shadow(color: .black.opacity(0.25), radius: 20, x: 8, y: 18).zIndex(0)
                    ForEach(symbols.indices, id: \.self) { index in
                        let angle = time * 0.36 + Double(index) * .pi * 2 / Double(symbols.count)
                        let depth = sin(angle)
                        VStack(spacing: 5) {
                            Image(systemName: symbols[index]).font(.system(size: 24, weight: .medium))
                                .frame(width: 58, height: 58).background(.white, in: RoundedRectangle(cornerRadius: 18))
                                .shadow(color: LabPalette.accent.opacity(0.16), radius: 12, y: 7)
                            Text(labels[index]).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(index % 2 == 0 ? LabPalette.accent : Color.teal)
                        .scaleEffect(0.85 + depth * 0.16)
                        .opacity(0.75 + depth * 0.2)
                        .offset(x: cos(angle) * Double(proxy.size.width * 0.39), y: sin(angle) * 88 - cos(angle) * 30)
                        .zIndex(depth > 0 ? 2 : -1)
                    }
                }.frame(width: proxy.size.width, height: proxy.size.height)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
