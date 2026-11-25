import Foundation

/// Bounds concurrent comic transfers/decodes without blocking cooperative threads.
actor ComicImageBudget {
    private let limit: Int
    private var active: Set<UUID> = []
    private var order: [UUID] = []
    private var waiting: [UUID: CheckedContinuation<Bool, Never>] = [:]

    init(limit: Int = 4) { self.limit = max(1, limit) }

    func acquire(_ id: UUID) async -> Bool {
        guard !Task.isCancelled else { return false }
        if active.count < limit {
            active.insert(id)
            return true
        }
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false); return }
                order.append(id)
                waiting[id] = continuation
            }
        }, onCancel: {
            Task { await self.cancelWaiting(id) }
        })
    }

    func release(_ id: UUID) {
        guard active.remove(id) != nil else { return }
        while active.count < limit, !order.isEmpty {
            let next = order.removeFirst()
            guard let continuation = waiting.removeValue(forKey: next) else { continue }
            active.insert(next)
            continuation.resume(returning: true)
        }
    }

    private func cancelWaiting(_ id: UUID) {
        guard let continuation = waiting.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        continuation.resume(returning: false)
    }
}
