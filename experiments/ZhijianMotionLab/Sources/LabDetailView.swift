import SwiftUI

/// A real navigation destination, not a second invisible geometry source under an overlay.
struct LabDetailView: View {
    @EnvironmentObject private var artwork: LabArtwork
    let book: LabBook
    let onRead: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ZStack(alignment: .bottomLeading) {
                    if let image = artwork.image(book.artwork) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 390).clipped()
                    }
                    LinearGradient(colors: [.clear, LabPalette.midnight], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 9) {
                        Text(book.genre.uppercased()).font(.caption).tracking(3).foregroundStyle(LabPalette.gold)
                        Text(book.title).font(.system(.largeTitle, design: .serif).weight(.semibold)).foregroundStyle(.white)
                        Text(book.author).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }.padding(26)
                }.frame(height: 390).clipped()
                VStack(alignment: .leading, spacing: 24) {
                    Text(book.tagline).font(.title3.weight(.medium)).foregroundStyle(.white)
                    Text(book.synopsis).font(.body).lineSpacing(8).foregroundStyle(.white.opacity(0.75))
                    Button(action: onRead) {
                        Label("试读这个故事", systemImage: "book.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                            .foregroundStyle(LabPalette.midnight).background(.white, in: Capsule())
                    }.buttonStyle(LabPressStyle())
                    Text("关于这个版本").font(.headline).foregroundStyle(.white)
                    Text("这是纸间的独立视觉实验。作品、章节均为原创离线样本；书源、漫画排版与音频仍在正式纸间中。这里不伪造评分、阅读天数或推荐服务。")
                        .font(.subheadline).lineSpacing(6).foregroundStyle(.white.opacity(0.6))
                }.padding(.horizontal, 26).padding(.bottom, 44)
            }
        }.background(LabPalette.midnight).ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline).preferredColorScheme(.dark)
    }
}

struct LabReaderView: View {
    @EnvironmentObject private var library: LabLibrary
    @Environment(\.dismiss) private var dismiss
    let book: LabBook
    @State private var chapter = 0
    @State private var paragraph = 0
    @State private var message: String?
    @State private var fontSize = 20.0

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text(book.chapters[chapter]).font(.system(.title2, design: .serif).weight(.semibold))
                        ForEach(book.paragraphs.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(book.paragraphs[index]).font(.system(size: fontSize, design: .serif)).lineSpacing(10)
                                HStack {
                                    Button {
                                        paragraph = index; library.savePosition(book: book, chapter: chapter, paragraph: index)
                                        message = "已记到这一段"
                                    } label: { Label(paragraph == index ? "当前位置" : "记到这里", systemImage: paragraph == index ? "bookmark.fill" : "bookmark") }
                                    Spacer()
                                    Button {
                                        library.saveQuote(book: book, paragraph: index); message = "已收进我的书笺"
                                    } label: { Image(systemName: "quote.bubble") }
                                        .accessibilityIdentifier("reader.quote.\(index)")
                                        .accessibilityLabel("保存第 \(index + 1) 段为书笺")
                                }.font(.caption).frame(minHeight: 44).foregroundStyle(LabPalette.accent)
                            }.id(index)
                        }
                        HStack {
                            Button("上一章") { changeChapter(-1, proxy: proxy) }.disabled(chapter == 0)
                            Spacer()
                            Text("\(chapter + 1) / \(book.chapters.count)").font(.caption)
                            Spacer()
                            Button("下一章") { changeChapter(1, proxy: proxy) }.disabled(chapter == book.chapters.count - 1)
                        }.frame(minHeight: 44)
                        Text("演示说明：点击「记到这里」保存段落，重新打开可定位；不是正式阅读器的自动 UTF-16 锚点引擎。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(26)
                }
                .onAppear {
                    let saved = library.position(for: book); chapter = saved.chapter; paragraph = saved.paragraph
                }
                .task {
                    do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                    proxy.scrollTo(paragraph, anchor: .top)
                }
            }
            .foregroundStyle(LabPalette.ink).background(Color(red: 0.98, green: 0.96, blue: 0.91))
            .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() }.accessibilityIdentifier("reader.close") }
                ToolbarItem(placement: .primaryAction) {
                    Button("字号") { fontSize = fontSize < 25 ? fontSize + 2 : 18 }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message { Text(message).font(.footnote).padding(12).frame(maxWidth: .infinity).background(.regularMaterial).accessibilityAddTraits(.updatesFrequently) }
            }
        }
        .preferredColorScheme(.light)
    }

    private func changeChapter(_ direction: Int, proxy: ScrollViewProxy) {
        let next = min(max(chapter + direction, 0), book.chapters.count - 1)
        chapter = next; paragraph = 0; library.savePosition(book: book, chapter: next, paragraph: 0)
        proxy.scrollTo(0, anchor: .top)
    }
}
