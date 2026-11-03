import SwiftUI

/// Real book identity remains visible while the gateway restores its actual chapter.
struct ReaderOpeningPage: View {
    let book: BookshelfBook
    var chapterTitle: String? = nil
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue
    private var paper: ReaderBackground { ReaderBackground(rawValue: paperRaw) ?? .white }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            BookJacket {
                AsyncBookCover(urlString: book.coverURL, width: 96, height: 136,
                    baseURLString: book.bookURL, sourceURLString: book.sourceURL, title: book.title)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("纸间 · 继续你的故事").font(.caption).foregroundStyle(.secondary)
                Text(book.title).font(.title.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(chapterTitle ?? ReadingHeroStatus.chapter(for: book)).font(.subheadline).foregroundStyle(.secondary)
            }
            Divider()
            ProgressView(chapterTitle == nil ? "正在恢复阅读位置" : "正在加载正文").font(.caption)
            Spacer(); Spacer()
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(paper.textColor(isNight: paper.isDark))
            .background(paper.color(isNight: paper.isDark).ignoresSafeArea())
            .environment(\.colorScheme, paper.isDark ? .dark : .light)
    }
}
