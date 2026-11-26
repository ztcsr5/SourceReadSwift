import SwiftUI

/// The date belongs to the edition, not to each book in its horizontal pager.
struct EditionMasthead<Actions: View>: View {
    let theme: AppVisualTheme
    @ViewBuilder let actions: (Date) -> Actions
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var phase
    @State private var date = Date()

    var body: some View {
        Group {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    if theme == .pineSootMagazine {
                        Text("纸间刊 · 书房日历").font(.caption2.weight(.semibold))
                    } else {
                        Text("\(date.formatted(EditionCalendar.weekday)) · 精装书房").font(.caption.weight(.semibold))
                    }
                    Text(theme == .pineSootMagazine ? EditionCalendar.issueDate(date) : date.formatted(EditionCalendar.monthDay))
                        .font(.system(.largeTitle, design: .serif).weight(.medium))
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions(date)
            }
            .foregroundStyle(theme.primaryInk)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in date = Date() }
        .onChange(of: phase) { if $0 == .active { date = Date() } }
    }
}

enum EditionCalendar {
    static let weekday = Date.FormatStyle.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN"))
    static let monthDay = Date.FormatStyle.dateTime.month(.wide).day().locale(Locale(identifier: "zh_CN"))

    static func issueDate(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.month, .day], from: date)
        let digits = Array("零一二三四五六七八九")
        func spell(_ value: Int) -> String {
            if value < 10 { return String(digits[value]) }
            return (value >= 20 ? String(digits[value / 10]) : "") + "十" + (value % 10 == 0 ? "" : String(digits[value % 10]))
        }
        guard let month = components.month, let day = components.day else { return date.formatted(monthDay) }
        let dayText = (20..<30).contains(day) ? "廿" + (day == 20 ? "" : String(digits[day - 20])) : spell(day)
        return "\(spell(month))月\(dayText)"
    }
}
