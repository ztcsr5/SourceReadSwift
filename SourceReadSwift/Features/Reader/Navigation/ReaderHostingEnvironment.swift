import SwiftUI

/// Transfer public presentation traits across hosting boundaries without copying SwiftUI's internal graph.
struct ReaderHostingEnvironment: ViewModifier {
    let values: EnvironmentValues

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, values.colorScheme)
            .environment(\.dynamicTypeSize, values.dynamicTypeSize)
            .environment(\.layoutDirection, values.layoutDirection)
            .environment(\.locale, values.locale)
            .environment(\.calendar, values.calendar)
            .environment(\.timeZone, values.timeZone)
            .environment(\.scenePhase, values.scenePhase)
            .environment(\.readingCoverHandoff, values.readingCoverHandoff)
    }
}
