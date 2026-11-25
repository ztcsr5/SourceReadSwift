import SwiftUI

/// Native momentum may cross multiple books; metadata commits only after scrolling settles.
struct HomeBookCarousel<Card: View>: View {
    struct Layout {
        let widthFraction: CGFloat
        let height: CGFloat
        let centered: Bool
    }

    let books: [BookshelfBook]
    @Binding var selection: String?
    let layout: Layout
    @ViewBuilder let card: (BookshelfBook, CGFloat) -> Card
    @State private var visibleID: String?
    @AppMotion private var motion

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, 560) * layout.widthFraction
            let margin = layout.centered ? max((geometry.size.width - width) / 2, 0) : AppTheme.pagePadding
            if books.count == 1, let book = books.first {
                card(book, width).frame(width: width).frame(maxHeight: .infinity).padding(.leading, margin)
            } else if #available(iOS 17, *) {
                observeSettling(in: ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(books) { book in
                            card(book, width).frame(width: width, height: layout.height).clipped().id(book.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, margin, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
                .scrollPosition(id: scrollSelection, anchor: layout.centered ? .center : .leading))
            } else {
                TabView(selection: legacyPageSelection) {
                    ForEach(books) { book in
                        card(book, width)
                            .frame(width: width, height: layout.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(book.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: geometry.size.width, height: layout.height)
            }
        }
        .frame(height: layout.height)
        .onAppear {
            if selection == nil || !books.contains(where: { $0.id == selection }) {
                selection = resolvedSelection
            }
            visibleID = resolvedSelection
        }
        .onChange(of: selection) { visibleID = $0 }
        .onChange(of: books.map(\.id)) { ids in
            if !ids.contains(selection ?? ""), let fallback = resolvedSelection {
                selection = fallback
            }
            if !ids.contains(visibleID ?? "") { visibleID = resolvedSelection }
        }
        .accessibilityIdentifier("home.books.carousel")
        .accessibilityScrollAction { edge in
            if edge == .leading { step(-1) }
            if edge == .trailing { step(1) }
        }
    }

    @ViewBuilder private func observeSettling<Content: View>(in content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .idle, let visibleID, selection != visibleID { selection = visibleID }
            }
        } else {
            content
        }
    }

    private var resolvedSelection: String? {
        books.first(where: { $0.id == selection })?.id ?? books.first?.id
    }

    private var legacyPageSelection: Binding<String> {
        Binding(
            get: { resolvedSelection ?? "" },
            set: { id in
                guard !id.isEmpty, selection != id else { return }
                selection = id
                visibleID = id
            }
        )
    }

    private var scrollSelection: Binding<String?> {
        Binding(get: { visibleID ?? resolvedSelection }, set: { id in
            guard let id else { return }
            visibleID = id
            if #unavailable(iOS 18) { selection = id }
        })
    }

    private func step(_ direction: Int) {
        let index = (books.firstIndex { $0.id == resolvedSelection } ?? 0) + direction
        guard books.indices.contains(index) else { return }
        withAnimation(motion.animation(.navigation)) { selection = books[index].id }
    }
}
