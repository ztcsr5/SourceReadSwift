import SwiftUI

struct ReadingHomeView: View {
    @EnvironmentObject private var library: LabLibrary
    @EnvironmentObject private var artwork: LabArtwork
    @Binding var selectedIndex: Int
    let onDetail: (LabBook) -> Void
    let onRead: (LabBook) -> Void
    private let canvas = Color(red: 0.12, green: 0.09, blue: 0.075)

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TabView(selection: $selectedIndex) {
                        ForEach(library.books.indices, id: \.self) { index in
                            hero(library.books[index], height: max(530, proxy.size.height * 0.75)).tag(index)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: max(530, proxy.size.height * 0.75))
                    HStack(spacing: 6) {
                        ForEach(library.books.indices, id: \.self) { index in
                            Capsule().fill(.white.opacity(index == selectedIndex ? 1 : 0.25)).frame(width: index == selectedIndex ? 22 : 5, height: 4)
                        }
                    }.padding(.top, 8).padding(.bottom, 24)
                    row("书架里的世界", books: library.books)
                    row("科幻与远方", books: library.books.filter { $0.genre.contains("科幻") })
                    row("童话与奇遇", books: library.books.filter { $0.genre.contains("童话") || $0.genre.contains("奇幻") })
                    Text("离线样本书库 · 不是在线推荐榜单\n封面来源 Open Library；试读样段不含原书正文。")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center).padding(24)
                }.padding(.bottom, 100)
            }.background(canvas).ignoresSafeArea(edges: .top)
        }
    }

    private func hero(_ book: LabBook, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            if let cover = artwork.image(book.artwork) {
                Image(uiImage: cover).resizable().scaledToFill().frame(height: height).clipped().accessibilityHidden(true)
            }
            LinearGradient(stops: [.init(color: .clear, location: 0.33), .init(color: canvas.opacity(0.45), location: 0.62), .init(color: canvas, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Text(book.title).font(.system(size: 32, weight: .semibold, design: .serif)).multilineTextAlignment(.center)
                Text("\(book.author) · \(book.genre)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                Text(book.synopsis).font(.system(size: 11)).lineSpacing(3).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 12) {
                    Button { onRead(book) } label: {
                        Label(library.snapshot.positions[book.id] == nil ? "体验阅读器" : "继续阅读", systemImage: "book.fill")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(canvas).background(.white, in: Capsule())
                    }.accessibilityIdentifier("home.read")
                    Button { onDetail(book) } label: {
                        Image(systemName: "arrow.up.right").font(.title3).frame(width: 48, height: 48).background(.white.opacity(0.14), in: Circle())
                    }.accessibilityLabel("查看\(book.title)简介").accessibilityIdentifier("home.detail")
                }.buttonStyle(LabPressStyle()).padding(.top, 5)
            }.foregroundStyle(.white).padding(.horizontal, 24).padding(.bottom, 10)
        }.frame(height: height).clipped()
    }

    private func row(_ title: String, books: [LabBook]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 18, weight: .semibold)).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(books) { book in
                        Button { onDetail(book) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                LabCover(book: book, radius: 8).frame(width: 105, height: 158)
                                Text(book.title).font(.caption.weight(.medium)).lineLimit(1)
                                Text(book.author).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            }.frame(width: 105)
                        }.buttonStyle(LabPressStyle())
                    }
                }.padding(.horizontal, 16)
            }
        }.foregroundStyle(.white).padding(.bottom, 26)
    }
}

struct ReadingDetailView: View {
    @EnvironmentObject private var artwork: LabArtwork
    @Environment(\.dismiss) private var dismiss
    let book: LabBook
    let onRead: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack(alignment: .topLeading) {
                    if let cover = artwork.image(book.artwork) {
                        Image(uiImage: cover).resizable().scaledToFill().frame(height: 280).clipped().accessibilityHidden(true)
                    }
                    LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                    }.padding(.leading, 16).padding(.top, 64).accessibilityLabel("返回书架").accessibilityIdentifier("detail.back")
                }.frame(height: 280).clipped()
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        LabCover(book: book).frame(width: 84, height: 126)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(book.title).font(.title2.bold())
                            Text(book.author).font(.subheadline)
                            Text(book.genre).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button(action: onRead) {
                        Label("体验阅读器", systemImage: "book.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.white).background(LabPalette.accent, in: Capsule())
                    }.accessibilityIdentifier("detail.read")
                    Text("书籍简介").font(.title3.bold())
                    Text(book.synopsis).lineSpacing(7)
                    Text("这是一本真实书籍的界面样本。试读页的文字是本实验编写的交互样段，不是原书正文；保存的书笺与阅读位置只属于这个测试 App。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("封面提供：Open Library · 具体版本与来源见实验设置").font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.bottom, 40)
            }
        }.ignoresSafeArea(edges: .top).background(LabPalette.paper).foregroundStyle(LabPalette.ink)
            .toolbar(.hidden, for: .navigationBar).preferredColorScheme(.light)
    }
}

struct ReadingSearchView: View {
    @EnvironmentObject private var library: LabLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onDetail: (LabBook) -> Void
    private var matches: [LabBook] { library.books.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            List(matches) { book in
                Button { dismiss(); onDetail(book) } label: {
                    HStack(spacing: 14) {
                        LabCover(book: book).frame(width: 42, height: 63)
                        VStack(alignment: .leading, spacing: 5) { Text(book.title); Text(book.author).font(.caption).foregroundStyle(.secondary) }
                    }.foregroundStyle(.primary)
                }
            }.searchable(text: $query, prompt: "搜索样本书籍或作者")
                .overlay { if matches.isEmpty { Text("没有匹配的样本书籍").foregroundStyle(.secondary) } }
                .navigationTitle("找一本书")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("离线书库").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("关闭") { dismiss() }.frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 20).background(LabPalette.paper)
        }
    }
}
