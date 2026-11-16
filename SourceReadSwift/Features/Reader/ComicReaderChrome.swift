import SwiftUI

/// Adapted from Aidoku's ReaderToolbarView (Skitty, 8/15/22).
/// SPDX-License-Identifier: GPL-3.0-only
struct ComicReaderChrome: View {
    struct PageDisplay {
        let index: Int
        let count: Int
        let isRightToLeft: Bool

        var number: Int { min(max(index + 1, 1), max(count, 1)) }
        var remaining: Int { max(count - number, 0) }
    }

    struct Actions {
        let close: () -> Void
        let showDirectory: () -> Void
        let showSettings: () -> Void
        let openChapterWebsite: (() -> Void)?
        let selectPage: (Int) -> Void
    }

    let chapterTitle: String
    let page: PageDisplay
    let actions: Actions

    @State private var scrubbedIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            if page.count > 0 { scrubber }
        }
        .transition(.opacity)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                HStack(spacing: 8) { closeButton; directoryButton }
                    .frame(width: 112, alignment: .leading)
                title
                    .frame(maxWidth: .infinity)
                settingsGroup
                    .frame(width: 112, alignment: .trailing)
            }
            HStack(spacing: 8) {
                closeButton
                directoryButton
                title.frame(maxWidth: .infinity)
                settingsButton.modifier(RootTabGlassSurface(outline: Circle()))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, ignoresSafeAreaEdges: .top)
    }

    private var title: some View {
        Text(chapterTitle)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityIdentifier("comic.chapterTitle")
    }

    private var closeButton: some View {
        iconButton("xmark", label: "返回书籍详情", identifier: "comic.return", action: actions.close)
            .modifier(RootTabGlassSurface(outline: Circle()))
    }

    private var directoryButton: some View {
        iconButton("list.bullet", label: "漫画目录", identifier: "comic.chapters", action: actions.showDirectory)
            .modifier(RootTabGlassSurface(outline: Circle()))
    }

    private var settingsButton: some View {
        Button(action: actions.showSettings) {
            Text("设置").font(.headline).frame(minWidth: 52, minHeight: 44)
        }
        .buttonStyle(ComicToolbarPressStyle())
        .accessibilityIdentifier("comic.readingMode")
        .accessibilityHint("调整漫画阅读模式、图片、背景与点击操作")
    }

    private var settingsGroup: some View {
        HStack(spacing: 0) {
            settingsButton
            if let open = actions.openChapterWebsite {
                iconButton("safari", label: "打开章节网页", identifier: "comic.chapterWebsite", action: open)
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 6)
        .modifier(RootTabGlassSurface(outline: Capsule()))
    }

    private var scrubber: some View {
        let displayed = PageDisplay(index: scrubbedIndex ?? page.index, count: page.count, isRightToLeft: page.isRightToLeft)
        return VStack(spacing: 0) {
            Slider(
                value: Binding(get: { Double(displayed.number - 1) }, set: { scrubbedIndex = Int($0.rounded()) }),
                in: 0...Double(max(page.count - 1, 1)), step: 1,
                onEditingChanged: finishScrubbing
            )
            .disabled(page.count <= 1)
            .frame(minHeight: 44)
            .accessibilityLabel("漫画页码")
            .accessibilityValue("\(displayed.number) / \(page.count)")
            .accessibilityIdentifier("comic.pageSlider")
            .accessibilityAdjustableAction { direction in
                guard page.count > 1 else { return }
                if direction == .increment { actions.selectPage(min(page.index + 1, page.count - 1)) }
                if direction == .decrement { actions.selectPage(max(page.index - 1, 0)) }
            }
            .environment(\.layoutDirection, page.isRightToLeft ? .rightToLeft : .leftToRight)
            .tint(.primary)

            ViewThatFits(in: .horizontal) {
                ZStack {
                    Text("\(displayed.number) / \(page.count)")
                        .accessibilityIdentifier("comic.pageNumber")
                    HStack {
                        Spacer()
                        Text("剩余 \(displayed.remaining) 页")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("comic.remainingPages")
                    }
                }
                HStack {
                    Text("\(displayed.number) / \(page.count)").accessibilityIdentifier("comic.pageNumber")
                    Spacer(minLength: 8)
                    Text("剩余 \(displayed.remaining) 页").foregroundStyle(.secondary)
                }
            }
            .font(.footnote.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .modifier(RootTabGlassSurface(outline: RoundedRectangle(cornerRadius: 32), isInteractive: true))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onChange(of: chapterTitle) { _ in scrubbedIndex = nil }
    }

    private func finishScrubbing(_ isEditing: Bool) {
        guard !isEditing, let target = scrubbedIndex else { return }
        if page.count > 1 { actions.selectPage(min(max(target, 0), page.count - 1)) }
        scrubbedIndex = nil
    }

    private func iconButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(ComicToolbarPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct ComicToolbarPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reducesMotion ? 0.96 : 1)
            .animation(reducesMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
