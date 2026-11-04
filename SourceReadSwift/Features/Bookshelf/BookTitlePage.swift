import SwiftUI

/// A real destination outside the chapter list. Viewing it never marks a book read.
struct BookTitlePage<ReaderDestination: View>: View {
    let book: SearchBook
    let chapterCount: Int
    let readLabel: String
    @ViewBuilder let reader: () -> ReaderDestination

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("纸间 · 藏书")
                    .font(.caption.weight(.semibold))
                    .tracking(4)
                    .foregroundStyle(AppTheme.accent)
                BookJacket {
                    AsyncBookCover(urlString: book.coverUrl, width: 164, height: 224,
                        baseURLString: book.bookUrl, sourceURLString: book.sourceUrl,
                        title: book.name, contentMode: .fit)
                }
                .accessibilityHidden(true)
                Text(book.name)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let author = book.author?.nilIfEmpty {
                    Text(author).font(.subheadline).foregroundStyle(.secondary)
                }
                if chapterCount > 0 {
                    Text("\(chapterCount) 章").font(.caption).foregroundStyle(.secondary)
                }
                if let introduction = ReadingDeskContent.introduction(from: book.intro) {
                    Divider().frame(maxWidth: 96)
                    Text(introduction).font(.subheadline).foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                NavigationLink { reader() } label: {
                    Label(readLabel, systemImage: "book")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(BookOpenPressStyle())
                .accessibilityIdentifier("bookTitlePage.read")
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 416)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(colors: [AppTheme.accent.opacity(0.10), AppTheme.background, AppTheme.background],
                startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(AppTheme.background)
                .ignoresSafeArea()
        }
        .navigationTitle("书籍扉页")
        .navigationBarTitleDisplayMode(.inline)
    }
}
