import SwiftUI

/// Defers settings construction behind a fixed-size, non-generic view boundary.
struct ReaderSettingsContent: View {
    private let buildContent: () -> AnyView

    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        // Do not evaluate here: otherwise the large tuple is still constructed
        // while GeometryReader / ScrollView / VStack all retain their copies.
        buildContent = { AnyView(content()) }
    }

    var body: some View {
        buildContent()
    }
}
