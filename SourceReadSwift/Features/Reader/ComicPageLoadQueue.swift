import Foundation

/// Keeps overlapping page loads alive while giving visible artwork the first available slots.
@MainActor
final class ComicPageLoadQueue<Page: Hashable> {
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let maximumLoads = 4
    private let maximumPrefetches = 2
    private var flights: [Page: Flight] = [:]
    private var visible: Set<Page> = []
    private var foreground: [Page] = []
    private var speculative: [Page] = []
    private var operation: (@MainActor (Page) async -> Void)?

    nonisolated init() {}

    func update(visible: [Page], prefetch: [Page], load: @escaping @MainActor (Page) async -> Void) {
        self.visible = Set(visible)
        operation = load
        var seen = Set<Page>()
        let ordered = (visible + prefetch).filter { seen.insert($0).inserted }
        let desired = Set(ordered)
        for page in Array(flights.keys) where !desired.contains(page) { cancel(page) }
        let speculativeFlights = ordered.filter { !self.visible.contains($0) && flights[$0] != nil }
        for page in speculativeFlights.dropFirst(maximumPrefetches) { cancel(page) }
        foreground = ordered.filter { self.visible.contains($0) && flights[$0] == nil }
        speculative = ordered.filter { !self.visible.contains($0) && flights[$0] == nil }

        // A newly exposed page must not wait behind a distant speculative transfer.
        var available = maximumLoads - flights.count
        for page in prefetch.reversed() where available < foreground.count {
            guard flights[page] != nil, !self.visible.contains(page) else { continue }
            cancel(page)
            available += 1
        }
        speculative = ordered.filter { !self.visible.contains($0) && flights[$0] == nil }
        drain()
    }

    func cancelAll() {
        foreground.removeAll()
        speculative.removeAll()
        operation = nil
        for page in Array(flights.keys) { cancel(page) }
    }

    private func cancel(_ page: Page) { flights.removeValue(forKey: page)?.task.cancel() }

    private func drain() {
        guard let operation else { return }
        while flights.count < maximumLoads {
            let page: Page
            let priority: TaskPriority
            if !foreground.isEmpty {
                page = foreground.removeFirst()
                priority = .userInitiated
            } else {
                guard flights.keys.filter({ !visible.contains($0) }).count < maximumPrefetches,
                      !speculative.isEmpty else { return }
                page = speculative.removeFirst()
                priority = .utility
            }
            let id = UUID()
            let task = Task(priority: priority) { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                await operation(page)
                guard let self, self.flights[page]?.id == id else { return }
                self.flights.removeValue(forKey: page)
                self.drain()
            }
            flights[page] = Flight(id: id, task: task)
        }
    }
}
