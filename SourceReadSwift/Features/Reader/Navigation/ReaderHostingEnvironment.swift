import SwiftUI

/// Transfer public presentation traits across hosting boundaries without copying SwiftUI's internal graph.
struct ReaderHostingEnvironment: ViewModifier, Equatable {
    private let colorScheme: ColorScheme?
    private let dynamicTypeSize: DynamicTypeSize
    private let layoutDirection: LayoutDirection
    private let locale: Locale
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let scenePhase: ScenePhase
    private let coverHandoff: ReadingCoverHandoff?

    init(values: EnvironmentValues, inheritsUIKitAppearance: Bool = false) {
        colorScheme = inheritsUIKitAppearance ? nil : values.colorScheme
        dynamicTypeSize = values.dynamicTypeSize
        layoutDirection = values.layoutDirection
        locale = values.locale
        calendar = values.calendar
        timeZone = values.timeZone
        scenePhase = values.scenePhase
        coverHandoff = values.readingCoverHandoff
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.colorScheme == rhs.colorScheme && lhs.dynamicTypeSize == rhs.dynamicTypeSize
            && lhs.layoutDirection == rhs.layoutDirection && lhs.locale == rhs.locale
            && lhs.calendar == rhs.calendar && lhs.timeZone == rhs.timeZone
            && lhs.scenePhase == rhs.scenePhase && lhs.coverHandoff === rhs.coverHandoff
    }

    @ViewBuilder func body(content: Content) -> some View {
        let sharedTraits = content
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.layoutDirection, layoutDirection)
            .environment(\.locale, locale)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, timeZone)
            .environment(\.scenePhase, scenePhase)
            .environment(\.readingCoverHandoff, coverHandoff)
        if let colorScheme { sharedTraits.environment(\.colorScheme, colorScheme) }
        else { sharedTraits }
    }
}
