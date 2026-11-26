import SwiftUI

/// Both editions use the same book, reader route and shelf action as the standard detail screen.
struct BoundEditionDetail<Actions: View>: View {
    let theme: AppVisualTheme
    let book: SearchBook
    let chapterCount: Int
    let progress: String?
    let status: String?
    let readerSourceID: String
    let namespace: Namespace.ID
    @ViewBuilder let actions: () -> Actions
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isMagazine: Bool { theme == .pineSootMagazine }
    private var source: String? { book.sourceUrl.hasPrefix("local://") ? "本地藏书" : book.sourceName.nilIfEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                jacket
                VStack(alignment: .leading, spacing: 7) {
                    Text(isMagazine ? (book.kind?.nilIfEmpty ?? "藏书档案") : "纸间 · 典藏档案")
                        .font(.caption.weight(.semibold)).foregroundStyle(theme.secondaryInk).lineLimit(2)
                    Text(book.name).font(.system(.title2, design: .serif).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("bookDetail.title")
                    if let author = book.author?.nilIfEmpty {
                        Text(author + " 著").font(.subheadline).foregroundStyle(theme.secondaryInk)
                    }
                    if isMagazine { actions() } else { badges }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if isMagazine { metrics } else { actions() }
        }
        .foregroundStyle(theme.primaryInk)
        .modifier(BoundEditionSection(theme: theme))
    }

    private var jacket: some View {
        EditorialBookJacket(height: 140, palette: .resolve(theme: theme), stance: .shelf) {
            AsyncBookCover(urlString: book.coverUrl, width: 99, height: 140, baseURLString: book.bookUrl,
                sourceURLString: book.sourceUrl, title: book.name, contentMode: .fill, prefersDeskRaster: true,
                cornerRadius: 3, usesPlainPlaceholder: true)
        }.bookHeroSource(readerSourceID, in: namespace)
    }

    private var badges: some View {
        let labels = [source, chapterCount > 0 ? "\(chapterCount) 章" : nil, status?.nilIfEmpty, book.wordCount?.nilIfEmpty].compactMap { $0 }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { badges(labels) }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) { badges(labels) }
        }
    }

    private func badges(_ labels: [String]) -> some View {
        ForEach(labels.indices, id: \.self) { index in
            Text(labels[index]).font(.caption2.weight(.semibold)).foregroundStyle(theme.secondaryInk)
                .lineLimit(2).padding(.horizontal, 7).padding(.vertical, 3).background(theme.controlFill, in: Capsule())
        }
    }

    private var metrics: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            metric("章节总数", chapterCount > 0 ? "\(chapterCount) 章" : "待获取")
            metric("当前书源", source ?? "未记录")
            metric("阅读进度", progress ?? "待开始")
        }.padding(.vertical, 13)
            .overlay(alignment: .top) { theme.secondaryInk.frame(height: 1) }
            .overlay(alignment: .bottom) { theme.controlBorder.frame(height: 1) }
    }

    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(theme.secondaryInk)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BoundEditionSection: ViewModifier {
    let theme: AppVisualTheme
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if theme == .hardcoverStudy {
            content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.dynamicColor(light: theme.cardHex, dark: theme.darkCardHex)
                    .opacity(reducesTransparency ? 1 : 0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else { content }
    }
}

struct EditionDetailTabVisibility: ViewModifier {
    let hides: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if hides { content.toolbar(.visible, for: .navigationBar).hideRootTabBar() } else { content }
    }
}

struct EditionPaperSamples: View {
    let theme: AppVisualTheme
    let bookTitle: String
    @State private var preview = ReaderBackground.sageGreen
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("外观微缩画廊").font(.subheadline.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text(bookTitle).font(.system(.subheadline, design: .serif)).lineLimit(2)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(preview.textColor).background(preview.color, in: RoundedRectangle(cornerRadius: 8))
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                ForEach([ReaderBackground.sageGreen, .linen, .dark]) { sample in
                    Button { preview = sample } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text("纸间").font(.system(.subheadline, design: .serif)); Spacer(minLength: 0)
                                if preview == sample { Image(systemName: "checkmark").font(.caption) }
                            }
                            Text(sample.title).font(.caption.weight(.semibold))
                        }.padding(8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .foregroundStyle(sample.textColor(isNight: false)).background(sample.color(isNight: false), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityLabel("预览" + sample.title)
                        .accessibilityAddTraits(preview == sample ? [.isSelected] : [])
                }
            }
        }.modifier(BoundEditionSection(theme: theme))
    }
}
