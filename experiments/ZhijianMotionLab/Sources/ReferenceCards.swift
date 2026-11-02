import SwiftUI

struct ReferenceTicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 7)
        let radius: CGFloat = 4
        for y in [CGFloat(0), rect.height] {
            path.addEllipse(in: CGRect(x: rect.width * 0.80 - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        for fraction in [CGFloat(0.04), 0.30, 0.57, 0.84] {
            path.addEllipse(in: CGRect(x: rect.width - radius, y: rect.height * fraction - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }
}

struct ReferenceTicket: View {
    let item: ReferenceMedia
    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            HStack(spacing: 10) {
                ReferencePoster(item: item, radius: 3).frame(width: height * 0.57, height: height - 16)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(item.overview).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                    Spacer(minLength: 0)
                    Text("\(item.release) 首播").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    HStack(spacing: 4) {
                        Text("IMDb").font(.system(size: 7, weight: .black)).foregroundStyle(.black).padding(2).background(.yellow)
                        Text(item.id == 82728 ? "9.3" : item.rating)
                        Text("TMDB").font(.system(size: 5, weight: .black)).foregroundStyle(.cyan)
                        Text(item.rating)
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.pink)
                        Text(item.rating)
                    }.font(.system(size: 10, weight: .medium))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                Rectangle().fill(.white.opacity(0.3)).frame(width: 1).overlay {
                    VStack(spacing: 4) { ForEach(0..<9) { _ in Rectangle().fill(.white.opacity(0.5)).frame(height: 4) } }
                }.frame(width: 1).padding(.vertical, 3)
                VStack(spacing: 2) {
                    ForEach(0..<25) { index in Rectangle().fill(.white.opacity(0.92)).frame(height: index % 5 == 0 ? 3 : 1) }
                }.frame(width: height * 0.23).padding(.horizontal, 8)
            }.padding(8).foregroundStyle(.white)
                .background(LinearGradient(colors: item.id == 87739 ? [Color(red: 0.23, green: 0.12, blue: 0.10), Color(red: 0.34, green: 0.22, blue: 0.2)] : [Color(red: 0.11, green: 0.33, blue: 0.39), Color(red: 0.12, green: 0.24, blue: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(ReferenceTicketShape(), style: FillStyle(eoFill: true)).clipped()
        }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 5)
        .accessibilityElement(children: .combine)
    }
}

struct ReferenceProgressCard: View {
    var body: some View {
        HStack(spacing: 11) {
            ReferencePoster(item: ReferenceMedia.item(106379)).frame(width: 65, height: 98)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("辐射").font(.headline)
                    Spacer()
                    Text("prime video").font(.system(size: 12, weight: .bold)).foregroundStyle(.blue)
                }
                Text("2024  动作冒险  科幻奇幻").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("第 2 季 集 8/8").font(.caption.weight(.semibold))
                        Capsule().fill(.black).frame(height: 4)
                    }
                    Label("完结", systemImage: "checkmark.rectangle.on.rectangle").font(.caption)
                        .padding(6).background(.black.opacity(0.08), in: Capsule())
                }
            }.padding(.vertical, 6)
        }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct ReferenceStatistics: View {
    let isAnimated: Bool
    var sampledTime: Double?
    @State private var origin = Date()
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimated || sampledTime != nil)) { context in
                let time = sampledTime ?? (isAnimated ? context.date.timeIntervalSince(origin) : 0)
                VStack(spacing: 22) {
                    today
                    trend
                    HStack(spacing: 16) {
                        smallCard("50", caption: "下载", images: true)
                        smallCard("50", caption: "订阅", images: true)
                    }
                    HStack(spacing: 16) {
                        genreCard("悬疑", hours: "3,000 小时", change: "↑3 小时")
                        genreCard("动作", hours: "2,000 小时", change: "↓1 小时")
                    }
                    today
                    trend
                }
                .padding(.horizontal, 20)
                .offset(y: -CGFloat(time * 28).truncatingRemainder(dividingBy: 370))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }.clipped().accessibilityElement(children: .ignore)
            .accessibilityLabel("引导用统计示例，不代表你的观看记录")
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("今天"); Spacer(); Text("2026 年 11 月 2 日") }.font(.system(size: 11, weight: .medium))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    metric("4.9", unit: "小时"); metric("5", unit: "部电影"); metric("8", unit: "集剧")
                }
                Spacer(minLength: 12)
                VStack(spacing: 6) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<18) { index in
                            Capsule().fill(index < 11 ? Color.gray.opacity(0.3) : (index % 3 == 0 ? Color.purple : Color.orange))
                                .frame(width: 4, height: index < 11 ? 4 : CGFloat([12, 25, 43, 35, 65, 82, 52][index - 11]))
                        }
                    }.frame(height: 85, alignment: .bottom)
                    HStack { Text("00:00"); Spacer(); Text("12:00"); Spacer(); Text("24:00") }.font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }.padding(18).background(cardSurface)
    }
    private var trend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近 7 天").font(.system(size: 18, weight: .bold))
            HStack(spacing: 5) { Text("4.9 小时").foregroundStyle(.secondary); Text("↓1.6 小时").foregroundStyle(.red) }.font(.system(size: 11, weight: .medium))
            curve.frame(height: 83).padding(.horizontal, -18).padding(.bottom, -18)
        }.padding(18).background(cardSurface).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private var curve: some View {
        GeometryReader { proxy in
            ZStack {
                ReferenceCurve(closes: true).fill(LinearGradient(colors: [.indigo.opacity(0.45), .indigo.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                ReferenceCurve(closes: false).stroke(.indigo, lineWidth: 2)
                Circle().fill(.white).overlay(Circle().stroke(.indigo, lineWidth: 2)).frame(width: 10, height: 10)
                    .position(x: proxy.size.width - 7, y: proxy.size.height * 0.67)
            }
        }
    }
    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.88))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white, lineWidth: 1))
            .shadow(color: .black.opacity(0.09), radius: 16, y: 6)
    }
    private func metric(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: 24, weight: .bold))
            Text(unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
    private func smallCard(_ value: String, caption: String, images: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 34, weight: .black)); Text(caption).font(.caption.weight(.semibold))
            HStack(spacing: -10) {
                ReferencePoster(item: ReferenceMedia.item(157336)).frame(width: 48, height: 65).rotationEffect(.degrees(-12))
                ReferencePoster(item: ReferenceMedia.item(82728)).frame(width: 48, height: 65).rotationEffect(.degrees(10))
            }.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 12)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(cardSurface)
    }
    private func genreCard(_ title: String, hours: String, change: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title).font(.headline); Spacer(minLength: 0); Text(change).font(.system(size: 9)).foregroundStyle(title == "悬疑" ? .green : .red) }
            Text(hours).font(.system(size: 11, weight: .semibold))
            curve.frame(height: 95).padding(.horizontal, -16).padding(.bottom, -16)
        }.padding(16).frame(maxWidth: .infinity).background(cardSurface).clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct ReferenceCurve: Shape {
    let closes: Bool
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height * 0.67))
            path.addCurve(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.38), control1: CGPoint(x: rect.width * 0.20, y: rect.height * 1.05), control2: CGPoint(x: rect.width * 0.33, y: rect.height * 0.63))
            path.addCurve(to: CGPoint(x: rect.width - 7, y: rect.height * 0.67), control1: CGPoint(x: rect.width * 0.76, y: -rect.height * 0.21), control2: CGPoint(x: rect.width * 0.85, y: rect.height * 0.27))
            if closes { path.addLine(to: CGPoint(x: rect.width, y: rect.height)); path.addLine(to: CGPoint(x: 0, y: rect.height)); path.closeSubpath() }
        }
    }
}
