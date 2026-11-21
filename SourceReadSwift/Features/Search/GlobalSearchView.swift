import SwiftUI

/// The global search entry uses the online book search and its existing filters.
struct GlobalSearchView: View {
    let viewModel: DiscoverViewModel
    var showsCloseButton = true

    var body: some View {
        DiscoverView(viewModel: viewModel, mode: .search, showsCloseButton: showsCloseButton)
    }
}
