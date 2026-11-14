import Foundation
import SwiftUI

/// Single shared minute clock for reader headers, footers, and comic overlays.
/// Leaves page views free of per-page `TimelineView(.everyMinute)` schedules and
/// stops ticking completely when no reader clock label is on screen.
@MainActor
final class ReaderSharedClock: ObservableObject {
    static let shared = ReaderSharedClock()

    @Published private(set) var now: Date

    private var activeSubscribers: Set<UUID> = []
    private var tickTask: Task<Void, Never>?

    init(initialDate: Date = Date()) {
        self.now = initialDate
    }

    func register(token: UUID) {
        let wasEmpty = activeSubscribers.isEmpty
        activeSubscribers.insert(token)
        if wasEmpty {
            let current = Date()
            if !Self.isSameMinute(current, now) {
                now = current
            }
            startTicking()
        }
    }

    func unregister(token: UUID) {
        activeSubscribers.remove(token)
        if activeSubscribers.isEmpty {
            tickTask?.cancel()
            tickTask = nil
        }
    }

    var activeSubscriberCount: Int {
        activeSubscribers.count
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let current = Date()
                let delay = Self.nextMinuteDelay(from: current)
                let nanoseconds = UInt64(max(delay, 0.25) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled, let self, !self.activeSubscribers.isEmpty else { break }
                self.now = Date()
            }
        }
    }

    static func nextMinuteDelay(from date: Date, calendar: Calendar = .current) -> TimeInterval {
        let components = calendar.dateComponents([.second, .nanosecond], from: date)
        let seconds = TimeInterval(components.second ?? 0)
        let nanos = TimeInterval(components.nanosecond ?? 0) / 1_000_000_000
        let remaining = 60.0 - seconds - nanos
        return remaining > 0.05 ? remaining : 60.0
    }

    static func isSameMinute(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .minute)
    }
}

/// Tiny leaf text view observing `ReaderSharedClock.shared` so minute updates
/// never re-evaluate surrounding reader page containers or headers.
struct ReaderMinuteClockText: View {
    @ObservedObject private var clock = ReaderSharedClock.shared
    @State private var token = UUID()

    var body: some View {
        Text(clock.now, format: .dateTime.hour().minute())
            .onAppear {
                clock.register(token: token)
            }
            .onDisappear {
                clock.unregister(token: token)
            }
    }
}
