import Foundation

/// Suspends async callers while synchronous JS callouts use libdispatch workers.
enum BlockingRuleExecutor {
    private static let marker = DispatchSpecificKey<Bool>()
    private static let queue: DispatchQueue = {
        let queue = DispatchQueue(label: "SourceReadSwift.source-rules", qos: .userInitiated, attributes: .concurrent)
        queue.setSpecific(key: marker, value: true)
        return queue
    }()

    static var isOnRuleQueue: Bool { DispatchQueue.getSpecific(key: marker) == true }

    static func run<Value: Sendable>(_ operation: @escaping @Sendable () -> Value) async -> Value {
        let isDiagnostic = SourceRequestContext.isDiagnostic
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = SourceRequestContext.$isDiagnostic.withValue(isDiagnostic) {
                    autoreleasepool(invoking: operation)
                }
                continuation.resume(returning: result)
            }
        }
    }
}
