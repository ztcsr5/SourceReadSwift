import SwiftUI

private struct ShelfOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// One set of book identities continuously morphs from depth field into a scrollable shelf.
struct ReadingCoverField: View {
    let blend: Double
    let isAnimated: Bool
    var sampledTime: Double?
    @State private var origin = Date()
    @State private var scrollOffset: CGFloat = 0
    private let columns: [CGFloat] = [0.72, 0.48, 0.44, 0.20, 0.03, 0.66, 0.99, 0.01, 0.98, 0.78, 0.99, 0.12, 0.56, 0.03, 0.34, 0.66, 0.95]
    private let rows: [CGFloat] = [0.65, 0.76, 0.28, 0.48, 0.69, 0.48, 0.70, 0.36, 0.73, 0.19, 0.40, 0.27, 0.23, 0.69, 0.82, 0.87, 0.42]

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isAnimated || sampledTime != nil)) { context in
                    let time = sampledTime ?? context.date.timeIntervalSince(origin)
                    ZStack(alignment: .top) {
                        ForEach(columns.indices, id: \.self) { index in
                            let pose = pose(index: index, time: time, size: proxy.size)
                            let book = LabBook.samples[index % LabBook.samples.count]
                            LabCover(book: book, radius: 6)
                                .frame(width: pose.width, height: pose.width * 1.5)
                                .shadow(color: .black.opacity(0.20 * (1 - blend) + 0.04), radius: 7 - 5 * blend, y: 5)
                                .blur(radius: pose.isDistant ? 3 * (1 - blend) : 0)
                                .scaleEffect(pose.scale).opacity(pose.opacity)
                                .rotation3DEffect(.degrees((1 - blend) * (index % 2 == 0 ? -5 : 5)), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                                .overlay(alignment: .bottom) {
                                    if index < 3 {
                                        VStack(spacing: 3) {
                                            Text(book.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                            Text(book.author).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                                        }.offset(y: 32).opacity(blend)
                                    }
                                }
                                .position(x: pose.x, y: pose.y + scrollOffset * (1 - blend))
                                .zIndex(blend > 0.9 ? 0 : Double(index % 3))
                        }
                        LabMark().foregroundStyle(.black).scaleEffect(1.05)
                            .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.49 + scrollOffset * (1 - blend))
                            .opacity(1 - blend).zIndex(10)
                        shelfModules(width: proxy.size.width)
                            .offset(y: proxy.size.width * 1.75 + 24)
                            .opacity(blend)
                    }
                    .frame(width: proxy.size.width, height: max(proxy.size.height, proxy.size.width * 1.75 + 584))
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: ShelfOffsetKey.self, value: -geometry.frame(in: .named("introShelf")).minY)
                    }
                }
            }
            .coordinateSpace(name: "introShelf")
            .scrollDisabled(blend < 0.98)
            .onPreferenceChange(ShelfOffsetKey.self) { scrollOffset = $0 }
            .accessibilityIdentifier("intro.shelfScroll")
        }.clipped()
    }

    private struct CoverPose {
        let x: CGFloat; let y: CGFloat; let width: CGFloat
        let scale: CGFloat; let opacity: Double; let isDistant: Bool
    }

    private func pose(index: Int, time: Double, size: CGSize) -> CoverPose {
        let amount = min(max(blend, 0), 1), width = size.width
        let isDistant = [1, 2, 4, 5, 7, 9, 10, 13, 15].contains(index)
        let wallX = columns[index] * width + CGFloat(cos(time * 0.14 + Double(index)) * 4)
        let wallY = rows[index] * size.height + CGFloat(sin(time * 0.31 + Double(index) * 0.72) * 16)
        let isFirst = index < 3, row = index < 3 ? 0 : (index - 3) / 4 + 1
        let column = isFirst ? index : (index - 3) % 4
        let gridWidth = width * (isFirst ? 0.266 : 0.182)
        let gridX = isFirst ? width * 0.167 + CGFloat(column) * width * 0.30 : width * 0.137 + CGFloat(column) * width * 0.244
        let gridY = isFirst ? width * 0.255 : width * 0.65 + CGFloat(row - 1) * width * 0.31
        func mix(_ first: CGFloat, _ second: CGFloat) -> CGFloat { first + (second - first) * amount }
        return CoverPose(x: mix(wallX, gridX), y: mix(wallY, gridY), width: mix(width * 0.18, gridWidth),
                         scale: mix(isDistant ? 0.80 : 1, 1), opacity: IntroPaging.blend(isDistant ? 0.55 : 1, 1, fraction: amount), isDistant: isDistant)
    }

    private func shelfModules(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("正在阅读 · 样式预览").font(.headline)
            HStack(spacing: 14) {
                LabCover(book: LabBook.samples[0]).frame(width: 65, height: 96)
                VStack(alignment: .leading, spacing: 8) {
                    Text(LabBook.samples[0].title).font(.title3.bold())
                    Text("读到哪里，就从哪里继续").font(.caption).foregroundStyle(.secondary)
                    Label("继续阅读", systemImage: "book.fill").font(.caption.weight(.semibold))
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
            Text("我的书单").font(.headline)
            HStack(spacing: 12) {
                ForEach(Array(LabBook.samples.prefix(4))) { book in
                    LabCover(book: book).aspectRatio(0.66, contentMode: .fit)
                }
            }
            Text("向上滑动，可以真的浏览这些模块。").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: width)
    }
}
