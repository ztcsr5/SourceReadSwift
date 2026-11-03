import SwiftUI

enum ReadingDeskSelection {
    static func books(from recent: [BookshelfBook]) -> [BookshelfBook] {
        let read = recent.filter { $0.lastReadAt != nil }
        return Array((read.isEmpty ? Array(recent.prefix(1)) : read).prefix(5))
    }

    static func resolve(_ selection: String?, in books: [BookshelfBook]) -> String {
        books.first(where: { $0.id == selection })?.id ?? books.first?.id ?? ""
    }
}

private struct ReadingDeskHeights: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

/// One book per viewport. Native paging owns the gesture; previews never mutate reading progress.
struct ReadingDeskPager<Card: View>: View {
    let books: [BookshelfBook]
    @Binding var selection: String
    var usesFloatingStyle = false
    @ViewBuilder var card: (BookshelfBook) -> Card
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppMotion private var motion
    @State private var heights: [String: CGFloat] = [:]

    private var index: Int { books.firstIndex(where: { $0.id == selection }) ?? 0 }
    private var height: CGFloat { max(books.compactMap { heights[$0.id] }.max() ?? (usesFloatingStyle ? 310 : books.contains(where: { $0.hasUpdates }) ? 196 : 176), 160) }
    private var current: BookshelfBook? { books.indices.contains(index) ? books[index] : books.first }

    var body: some View {
        VStack(spacing: 4) {
            if books.count <= 1 || typeSize.isAccessibilitySize || motion.reducesMotion {
                if let current { card(current) }
            } else if #available(iOS 17.0, *), usesFloatingStyle {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(books) { book in
                            measuredCard(book).containerRelativeFrame(.horizontal).id(book.id)
                        }
                    }.scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: Binding<String?>(get: { selection }, set: { if let id = $0 { selection = id } }))
                .frame(height: height)
                .onPreferenceChange(ReadingDeskHeights.self, perform: updateHeights)
                .accessibilityIdentifier("bookshelf.readingPager")
            } else {
                TabView(selection: $selection) {
                    ForEach(books) { book in
                        measuredCard(book).tag(book.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: height)
                .onPreferenceChange(ReadingDeskHeights.self, perform: updateHeights)
            }
            if books.count > 1 {
                HStack(spacing: 8) {
                    Text("最近阅读 · \(index + 1) / \(books.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    step(-1, symbol: "chevron.left", title: "上一本最近阅读")
                    step(1, symbol: "chevron.right", title: "下一本最近阅读")
                }
            }
        }
        .onChange(of: typeSize) { _ in heights = [:] }
        .onChange(of: usesFloatingStyle) { _ in heights = [:] }
        .onChange(of: books.map(\.id)) { ids in heights = heights.filter { ids.contains($0.key) } }
    }

    private func measuredCard(_ book: BookshelfBook) -> some View {
        card(book).fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ReadingDeskHeights.self, value: [book.id: proxy.size.height])
                }
            }
    }

    private func updateHeights(_ measured: [String: CGFloat]) {
        for (id, value) in measured where value.isFinite && value > 0 {
            if abs((heights[id] ?? 0) - value) > 0.5 { heights[id] = value }
        }
    }

    private func step(_ direction: Int, symbol: String, title: String) -> some View {
        Button {
            guard books.indices.contains(index + direction) else { return }
            withAnimation(motion.animation(.navigation)) { selection = books[index + direction].id }
        } label: {
            Image(systemName: symbol).font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.08), in: Circle())
        }
        .buttonStyle(AppPressStyle()).accessibilityLabel(title)
        .disabled(!books.indices.contains(index + direction))
        .accessibilityHint("仅切换书桌预览，不更改阅读进度")
    }
}
