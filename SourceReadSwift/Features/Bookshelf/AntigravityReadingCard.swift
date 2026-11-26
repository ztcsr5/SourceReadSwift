import SwiftUI

/// Four reference compositions share real book state and their parent reading action.
struct AntigravityReadingCard: View {
    let book: BookshelfBook
    let theme: AppVisualTheme
    var heroNamespace: Namespace.ID? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(PerformanceMode.defaultsKey) private var performanceMode = false
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24

    private var fraction: Double? { AtelierReadingProgress.fraction(for: book) }
    private var coverHeight: CGFloat { typeSize.isAccessibilitySize ? 174 : 212 }
    private var readingLabel: String { book.lastReadAt == nil ? "开始阅读" : "继续阅读" }

    var body: some View {
        composition
            .foregroundStyle(theme.primaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("轻点继续阅读，长按管理书籍")
            .accessibilityIdentifier("home.theme.\(theme.rawValue)")
    }

    @ViewBuilder private var composition: some View {
        switch theme {
        case .inkstone: inkstone
        case .hardcoverStudy: hardcoverStudy
        case .pineSootMagazine: magazine
        default: porcelain
        }
    }

    private var porcelain: some View {
        VStack(spacing: 12) {
            VStack(spacing: -3) {
                bookCover(height: coverHeight)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                glassShelf.frame(maxWidth: 232).frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 5) {
                title.multilineTextAlignment(.center)
                author.multilineTextAlignment(.center)
                chapter.multilineTextAlignment(.center)
            }
            HStack(spacing: 14) {
                readingAction()
                progressBadge
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    private var inkstone: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("今日书案").font(theme.titleFont(size: 16, weight: .medium))
                Spacer()
                Text("纸间 / 藏书").font(.caption2).tracking(1)
                    .foregroundStyle(theme.secondaryInk)
            }
            rule
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
            layout {
                VStack(alignment: .leading, spacing: 12) {
                    title
                    Rectangle().fill(theme.primaryInk).frame(width: 42, height: 1)
                        .accessibilityHidden(true)
                    author
                    chapter
                    readingAction()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: -2) {
                    bookCover(height: typeSize.isAccessibilitySize ? 174 : 176)
                        .padding(.horizontal, 8)
                    stoneShelf.frame(width: 146, height: 16)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
            }
            progressRail
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
        .background(alignment: .topTrailing) { windowLight }
    }

    private var hardcoverStudy: some View {
        VStack(spacing: -24) {
            bookCover(height: typeSize.isAccessibilitySize ? 180 : 220)
                .padding(.horizontal, 12)
                .shadow(color: theme.primaryInk.opacity(performanceMode ? 0 : 0.12), radius: 7, y: 4)
                .zIndex(1)
            VStack(spacing: 8) {
                editionTitle.multilineTextAlignment(.center)
                Text([book.author.nilIfEmpty, chapterCount].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(theme.secondaryInk)
                HStack(spacing: 12) {
                    editionAction
                    Text(ReadingHeroStatus.progressValue(for: book)).font(.caption.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 10).frame(minHeight: 42).background(theme.controlFill, in: Capsule())
                }
                .padding(.top, 2)
            }
            .padding(.top, 32)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.card.opacity(reducesTransparency || contrast == .increased ? 1 : 0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(theme.controlBorder.opacity(0.35), lineWidth: 0.5)
                    }
            }
            .shadow(color: theme.primaryInk.opacity(performanceMode || reducesTransparency ? 0 : 0.055), radius: 12, y: 5)
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var magazine: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                VStack(alignment: .leading, spacing: 12) {
                    Text("今日在读").font(.caption.weight(.bold)).foregroundStyle(theme.primaryInk)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(theme.controlFill)
                    editionTitle
                    VStack(alignment: .leading, spacing: 4) {
                        author
                        Text([chapterCount, ReadingHeroStatus.progressValue(for: book)].compactMap { $0 }.joined(separator: " · "))
                    }.font(.caption).foregroundStyle(theme.secondaryInk).padding(.leading, 8)
                        .overlay(alignment: .leading) { Rectangle().fill(theme.secondaryInk).frame(width: 1) }
                    editionAction
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                bookCover(height: typeSize.isAccessibilitySize ? 160 : 180)
                    .padding(.trailing, 3)
            }
            rule
        }
        .padding(.top, 4)
    }

    private var chapterCount: String? { book.totalChapters > 0 ? "全书 \(book.totalChapters) 章" : nil }

    private var editionTitle: some View {
        Text(book.title).font(.system(.title2, design: .serif).weight(.semibold))
            .lineLimit(typeSize.isAccessibilitySize ? nil : 3).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var editionAction: some View {
        let chapter = book.lastReadAt != nil && book.totalChapters > 0
            ? min(max(book.currentChapterIndex, 0), book.totalChapters - 1) + 1 : nil
        return HStack(spacing: 4) {
            Text(theme == .pineSootMagazine && book.lastReadAt != nil ? "翻开续读" : readingLabel)
            if let chapter { Text("· 第 \(chapter) 章") }
            if theme == .pineSootMagazine { Spacer(minLength: 0); Image(systemName: "arrow.right").accessibilityHidden(true) }
        }
        .accessibilityLabel(readingLabel + (chapter.map { "，第 \($0) 章" } ?? ""))
        .font(.subheadline.weight(.bold)).foregroundStyle(AppTheme.prominentInk)
        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 44)
        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: theme == .pineSootMagazine ? 5 : 24))
    }

    private var title: some View {
        Text(book.title)
            .font(theme.titleFont(size: titleSize, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var author: some View {
        if let author = book.author.nilIfEmpty {
            Text(author).font(.subheadline).foregroundStyle(theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chapter: some View {
        Text(ReadingHeroStatus.chapter(for: book))
            .font(.caption).foregroundStyle(theme.secondaryInk)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func readingAction() -> some View {
        HStack(spacing: 8) {
            Text(readingLabel).font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "arrow.right").font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(AppTheme.prominentInk)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(AppTheme.prominentFill, in: Capsule())
    }

    @ViewBuilder private var progressBadge: some View {
        if let fraction {
            ZStack {
                Circle().stroke(theme.controlBorder, lineWidth: 2)
                Circle().trim(from: 0, to: CGFloat(fraction))
                    .stroke(theme.primaryInk, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(ReadingHeroStatus.progressValue(for: book))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
            }
            .frame(width: 44, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ReadingHeroStatus.progress(for: book))
        } else {
            Text(ReadingHeroStatus.progressValue(for: book))
                .font(.caption).foregroundStyle(theme.secondaryInk)
        }
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ReadingHeroStatus.progress(for: book))
                .font(.caption.monospacedDigit()).foregroundStyle(theme.secondaryInk)
            if let fraction {
                ProgressView(value: fraction).tint(theme.primaryInk)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func bookCover(height: CGFloat) -> some View {
        let cover = EditorialBookJacket(height: height, palette: .resolve(theme: theme), stance: .shelf) {
            AsyncBookCover(urlString: book.coverURL, width: height * 2 / 3, height: height,
                baseURLString: book.bookURL, sourceURLString: book.sourceURL,
                title: book.title, prefersDeskRaster: true, cornerRadius: 3, usesPlainPlaceholder: true)
        }
        if let heroNamespace {
            cover.bookHeroSource("continue|" + book.id, in: heroNamespace)
        } else {
            cover
        }
    }

    @ViewBuilder private var glassShelf: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        if reducesTransparency || contrast == .increased || performanceMode {
            shape.fill(AppTheme.card).overlay(shape.strokeBorder(theme.controlBorder, lineWidth: 0.5))
        } else {
            shape.fill(.thinMaterial)
                .overlay(shape.fill(AppTheme.card.opacity(0.35)))
                .overlay(shape.strokeBorder(theme.controlBorder, lineWidth: 0.5))
        }
    }

    private var stoneShelf: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(LinearGradient(colors: [AppTheme.card, theme.controlFill],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .top) { rule }
            .overlay {
                Rectangle().fill(theme.controlBorder.opacity(0.65))
                    .frame(width: 160, height: 0.5).rotationEffect(.degrees(-8))
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var rule: some View {
        Rectangle().fill(theme.primaryInk.opacity(contrast == .increased ? 0.65 : 0.24))
            .frame(height: 0.5).accessibilityHidden(true)
    }

    private var windowLight: some View {
        Canvas { context, size in
            for offset in [CGFloat(-90), 20, 130] {
                var shadow = Path()
                shadow.move(to: CGPoint(x: offset, y: 0))
                shadow.addLine(to: CGPoint(x: offset + 12, y: 0))
                shadow.addLine(to: CGPoint(x: offset + size.width, y: size.height))
                shadow.addLine(to: CGPoint(x: offset + size.width - 12, y: size.height))
                shadow.closeSubpath()
                context.fill(shadow, with: .color(theme.primaryInk.opacity(scheme == .dark ? 0.08 : 0.035)))
            }
        }
        .frame(height: 160).clipped()
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
