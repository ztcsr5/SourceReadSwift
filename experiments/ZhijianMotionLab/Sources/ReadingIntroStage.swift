import SwiftUI

/// This animatable value is the finger's actual position, not a movie playback time.
struct ReadingIntroStage: View, Animatable {
    var position: Double
    let isAnimated: Bool
    let isDragging: Bool
    let chapter: Int
    let onNextChapter: () -> Void
    var sampledTime: Double?
    @State private var showsTicketReverse = false

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ReadingCoverField(blend: min(max(position, 0), 1), isAnimated: isAnimated && !isDragging && position < 0.99, sampledTime: sampledTime)
                    .opacity(min(max(2 - position, 0), 1)).allowsHitTesting(position < 1.15)
                tickets(size: proxy.size).opacity(visibility(2)).offset(x: (2 - position) * 18)
                    .allowsHitTesting(abs(position - 2) < 0.1)
                progressCard.frame(height: proxy.size.width * 0.32).padding(.horizontal, 15)
                    .opacity(visibility(3)).offset(x: (3 - position) * 18)
                    .allowsHitTesting(abs(position - 3) < 0.1)
                ReadingOrbitIcons(isAnimated: isAnimated && !isDragging && abs(position - 4) < 0.9, drawsForeground: false, sampledTime: sampledTime)
                    .opacity(visibility(4)).allowsHitTesting(false)
                centralBook(size: proxy.size).allowsHitTesting(false)
                ReadingOrbitIcons(isAnimated: isAnimated && !isDragging && abs(position - 4) < 0.9, drawsForeground: true, sampledTime: sampledTime)
                    .opacity(visibility(4)).allowsHitTesting(false)
                ReadingStatistics().opacity(visibility(5)).offset(y: (5 - position) * 25)
                    .scaleEffect(0.94 + 0.06 * visibility(5)).allowsHitTesting(position > 4.9)
            }
        }.clipped()
    }

    private func visibility(_ scene: Double) -> Double { min(max(1 - abs(position - scene), 0), 1) }

    private func tickets(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<3) { index in
                Button {
                    withAnimation(isAnimated ? .easeInOut(duration: 0.22) : nil) { showsTicketReverse.toggle() }
                } label: {
                    ReadingTicket(book: LabBook.samples[index], hidesCover: index == 0, showsReverse: showsTicketReverse)
                        .frame(width: size.width * 0.89, height: size.width * 0.34)
                }.buttonStyle(.plain)
                    .rotationEffect(.degrees(index == 0 ? 0 : (index == 1 ? -4 : 3)))
                    .offset(x: index == 2 ? 10 : 0, y: CGFloat(index - 1) * size.width * 0.29 + CGFloat(2 - position) * CGFloat(index + 1) * 20)
                    .zIndex(Double(3 - index))
                    .accessibilityLabel("翻转藏书票 \(index + 1)")
                    .accessibilityValue(showsTicketReverse ? "背面" : "正面")
                    .accessibilityIdentifier("intro.ticket.\(index)")
            }
        }.frame(width: size.width, height: size.height)
    }

    private var progressCard: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 65, height: 98)
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(LabBook.samples[0].title).font(.headline); Spacer(); Text("阅读进度").font(.caption).foregroundStyle(.indigo) }
                Text("交互样段 · 不是原书目录").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("样段 \(chapter + 1) / 3").font(.caption.weight(.semibold)).accessibilityIdentifier("intro.chapter")
                HStack(spacing: 10) {
                    ProgressView(value: Double(chapter + 1), total: 3).tint(.black)
                    Button(chapter == 2 ? "回到开头" : "翻一段", action: onNextChapter)
                        .font(.caption.weight(.medium)).frame(minWidth: 60, minHeight: 44)
                        .accessibilityIdentifier("intro.nextChapter")
                }
            }.padding(.vertical, 4)
        }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func centralBook(size: CGSize) -> some View {
        let orbit = min(max(position - 3, 0), 1)
        let ticket = min(max(position - 2, 0), 1)
        let ticketWidth = Double(size.width * 0.34 * 0.56)
        let width = IntroPaging.blend(IntroPaging.blend(ticketWidth, 65, fraction: ticket), Double(size.width * 0.29), fraction: orbit)
        let ticketX = Double(size.width * 0.055) + 8 + ticketWidth * 0.5
        let x = IntroPaging.blend(IntroPaging.blend(ticketX, 57.5, fraction: ticket), Double(size.width * 0.5), fraction: orbit)
        let y = IntroPaging.blend(Double(size.height * 0.5 - size.width * 0.29), Double(size.height * 0.5), fraction: ticket)
        let opacity = min(max(position - 1, 0), 1) * min(max(5 - position, 0), 1)
        return LabCover(book: LabBook.samples[0], radius: 8)
            .frame(width: width, height: width * 1.5)
            .rotation3DEffect(.degrees(-6 * orbit), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .shadow(color: .black.opacity(0.18 * orbit), radius: 14, y: 9)
            .position(x: x, y: y).opacity(opacity)
    }
}

private struct ReadingOrbitIcons: View {
    let isAnimated: Bool
    let drawsForeground: Bool
    var sampledTime: Double?
    private let symbols = ["doc.text", "books.vertical", "headphones", "doc.richtext", "network"]
    private let labels = ["TXT", "EPUB", "有声", "PDF", "书源"]
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isAnimated || sampledTime != nil)) { context in
                let time = sampledTime ?? context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(labels.indices, id: \.self) { index in
                        let angle = time * 0.40 + Double(index) * .pi * 2 / Double(labels.count)
                        let depth = sin(angle)
                        if (depth > 0) == drawsForeground {
                        VStack(spacing: 5) {
                            Image(systemName: symbols[index]).font(.system(size: 25, weight: .medium))
                                .frame(width: 52, height: 52).background(.white, in: RoundedRectangle(cornerRadius: 15))
                                .shadow(color: .indigo.opacity(0.16), radius: 10, y: 5)
                            Text(labels[index]).font(.system(size: 9, weight: .semibold))
                        }.foregroundStyle(index % 2 == 0 ? Color.indigo : Color.teal)
                            .scaleEffect(0.86 + depth * 0.14).opacity(0.80 + depth * 0.16)
                            .offset(x: cos(angle) * Double(proxy.size.width * 0.35), y: sin(angle) * 105 - cos(angle) * 18)
                            .zIndex(depth > 0 ? 1 : -1)
                        }
                    }
                }.frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}
