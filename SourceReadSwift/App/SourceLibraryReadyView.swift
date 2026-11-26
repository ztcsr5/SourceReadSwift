import SwiftUI

/// Source tools wait for restoration while the cached bookshelf remains usable.
struct SourceLibraryReadyView<Content: View>: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    private let showsCloseButton: Bool
    private let content: () -> Content

    init(showsCloseButton: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.showsCloseButton = showsCloseButton
        self.content = content
    }

    var body: some View {
        Group {
            if appState.isSourceLibraryLoading {
                ProgressView("正在恢复书源")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pageBackground()
                    .accessibilityIdentifier("sources.loading")
                    .overlay(alignment: .topTrailing) {
                        if showsCloseButton {
                            Button("关闭") { dismiss() }
                                .frame(minWidth: 44, minHeight: 44).padding()
                                .accessibilityIdentifier("globalSearch.close")
                        }
                    }
            } else {
                content()
            }
        }
    }
}
