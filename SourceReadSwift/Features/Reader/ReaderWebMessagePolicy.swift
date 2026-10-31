import Foundation

enum ReaderWebMessagePolicy {
    static func matchesRevision(_ received: String?, expected: String) -> Bool {
        !expected.isEmpty && received == expected
    }

    static func matchesRequest(_ received: String?, pending: String?) -> Bool {
        guard let pending, !pending.isEmpty else { return false }
        return received == pending
    }
}
