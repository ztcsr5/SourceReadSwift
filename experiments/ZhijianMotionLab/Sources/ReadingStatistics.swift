import SwiftUI

struct ReadingStatistics: View {
    @State private var showsWeek = false
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                HStack {
                    Text("阅读看板 · 样式演示").font(.caption.weight(.medium))
                    Spacer()
                    Button(showsWeek ? "切换今日" : "切换本周") { showsWeek.toggle() }
                        .font(.caption).frame(minWidth: 70, minHeight: 44).accessibilityIdentifier("intro.stats.period")
                }.padding(.horizontal, 4)
                VStack(alignment: .leading, spacing: 18) {
                    Text(showsWeek ? "本周阅读" : "今日阅读").font(.headline)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(showsWeek ? "168" : "42").font(.system(size: 34, weight: .bold))
                                Text("分钟").foregroundStyle(.secondary)
                            }.accessibilityIdentifier("intro.stats.minutes")
                            Text(showsWeek ? "示例 7 天累计" : "示例 3 个章节").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(0..<7) { index in
                                Capsule().fill(index % 2 == 0 ? Color.indigo : Color.orange)
                                    .frame(width: 7, height: CGFloat([17, 30, 24, 48, 58, 41, 72][index]))
                            }
                        }.frame(height: 80, alignment: .bottom)
                    }
                }.padding(20).background(card)
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近 7 天").font(.title3.bold())
                    Text("把每一次翻页，连成一条线。").font(.caption).foregroundStyle(.secondary)
                    trend.frame(height: 100).padding(.horizontal, -20).padding(.bottom, -20)
                }.padding(20).background(card).clipShape(RoundedRectangle(cornerRadius: 20))
                HStack(spacing: 16) {
                    metric("3", title: "演示章节", symbol: "book.closed")
                    metric("7", title: "样本书籍", symbol: "books.vertical")
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("阅读日历").font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 14), spacing: 5) {
                        ForEach(0..<56) { index in
                            RoundedRectangle(cornerRadius: 3).fill(Color.indigo.opacity(index % 5 == 0 ? 0.08 : Double(index % 4 + 1) * 0.18))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    Text("此处为引导示意，不冒充你的阅读历史。").font(.caption2).foregroundStyle(.secondary)
                }.padding(20).background(card)
            }.padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 180)
        }.accessibilityIdentifier("intro.statsScroll")
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.91))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white, lineWidth: 1))
            .shadow(color: .black.opacity(0.09), radius: 14, y: 5)
    }
    private var trend: some View {
        GeometryReader { proxy in
            ZStack {
                ReadingTrend(closes: true).fill(LinearGradient(colors: [.indigo.opacity(0.42), .indigo.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                ReadingTrend(closes: false).stroke(.indigo, lineWidth: 2)
                Circle().fill(.white).overlay(Circle().stroke(.indigo, lineWidth: 2))
                    .frame(width: 10, height: 10).position(x: proxy.size.width - 7, y: proxy.size.height * 0.64)
            }
        }
    }
    private func metric(_ value: String, title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.indigo)
            Text(value).font(.system(size: 32, weight: .bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(card)
    }
}

private struct ReadingTrend: Shape {
    let closes: Bool
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height * 0.74))
            path.addCurve(to: CGPoint(x: rect.width * 0.45, y: rect.height * 0.40), control1: CGPoint(x: rect.width * 0.15, y: rect.height * 1.02), control2: CGPoint(x: rect.width * 0.30, y: rect.height * 0.55))
            path.addCurve(to: CGPoint(x: rect.width - 7, y: rect.height * 0.64), control1: CGPoint(x: rect.width * 0.70, y: -rect.height * 0.15), control2: CGPoint(x: rect.width * 0.85, y: rect.height * 0.21))
            if closes { path.addLine(to: CGPoint(x: rect.width, y: rect.height)); path.addLine(to: CGPoint(x: 0, y: rect.height)); path.closeSubpath() }
        }
    }
}
