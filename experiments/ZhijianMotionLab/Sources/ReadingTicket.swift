import SwiftUI

struct ReadingStubShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 8)
        for y in [CGFloat(0), rect.height] {
            path.addEllipse(in: CGRect(x: rect.width * 0.80 - 5, y: y - 5, width: 10, height: 10))
        }
        for fraction in [CGFloat(0.06), 0.34, 0.62, 0.90] {
            path.addEllipse(in: CGRect(x: rect.width - 4, y: rect.height * fraction - 4, width: 8, height: 8))
        }
        return path
    }
}

/// A bookplate, not a movie rating or a pre-recorded image of a ticket.
struct ReadingTicket: View {
    let book: LabBook
    var hidesCover = false
    var showsReverse = false
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 10) {
                LabCover(book: book, radius: 3).opacity(hidesCover ? 0 : 1)
                    .frame(width: proxy.size.height * 0.56, height: proxy.size.height - 16)
                VStack(alignment: .leading, spacing: 6) {
                    Text(showsReverse ? "藏书票背面" : book.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(showsReverse ? "愿每一次翻页，都遇见一个更大的世界。" : book.author)
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                    Spacer(minLength: 0)
                    Text(showsReverse ? "纸间原创书笺样段 · 非原书摘录" : book.genre)
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    Text("EX LIBRIS  /  纸间藏书票").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(0.6)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1).padding(.vertical, 3)
                VStack(spacing: 2) {
                    ForEach(0..<23) { index in Rectangle().fill(.white.opacity(0.9)).frame(height: index % 5 == 0 ? 3 : 1) }
                }.frame(width: proxy.size.height * 0.20).padding(.horizontal, 8)
            }.padding(8).foregroundStyle(.white)
                .background(LinearGradient(colors: [Color(red: 0.11, green: 0.30, blue: 0.34), Color(red: 0.12, green: 0.21, blue: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(ReadingStubShape(), style: FillStyle(eoFill: true)).clipped()
        }.shadow(color: .black.opacity(0.2), radius: 8, y: 6)
    }
}
