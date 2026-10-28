import Foundation

/// Legado `concurrentRate`（并发率）规则。
///
/// 与 Android 版 `ConcurrentRateLimiter.kt` 保持一致：
/// - 空串 / `"0"` / 缺省：不限速；
/// - `"500"`：同一时刻只允许一个请求，两次请求的开始时间至少相隔 500 ms；
/// - `"3/1000"`：1000 ms 窗口内最多 3 次请求，窗口从第一次请求开始计时。
///
/// 无法解析的值按不限速处理：坏数据不应该让整个书源不可用。
struct SourceRateRule: Equatable, Sendable {
    /// 窗口内允许的请求数；间隔模式固定为 1。
    let limit: Int
    /// 窗口长度（纳秒）。
    let windowNanoseconds: UInt64
    /// true = `次数/毫秒` 窗口模式；false = 串行间隔模式。
    let isWindowed: Bool
    let rawValue: String

    private static let maximumWindowMilliseconds = 3_600_000

    init?(_ raw: String?) {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "0" else { return nil }

        if let slash = trimmed.firstIndex(of: "/") {
            let countText = String(trimmed[..<slash]).trimmingCharacters(in: .whitespaces)
            let windowText = String(trimmed[trimmed.index(after: slash)...])
            guard let count = Int(countText),
                  count > 0,
                  let milliseconds = Self.milliseconds(windowText) else { return nil }
            limit = count
            windowNanoseconds = UInt64(milliseconds) * 1_000_000
            isWindowed = true
        } else {
            guard let milliseconds = Self.milliseconds(trimmed) else { return nil }
            limit = 1
            windowNanoseconds = UInt64(milliseconds) * 1_000_000
            isWindowed = false
        }
        rawValue = trimmed
    }

    private static func milliseconds(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return min(value, maximumWindowMilliseconds)
    }
}

/// 按书源隔离的请求节流器。
///
/// Legado 在 `AnalyzeUrl` 发出请求前取号（`ConcurrentRateLimiter`），搜索、目录、
/// 正文三条链路共享同一个源的窗口；这里用 `rateLimitKey`（书源 URL）做同样的隔离。
/// 间隔模式还要求同一时刻只有一个在途请求，因此调用方必须成对调用
/// `acquire` / `release`。
final class SourceRateLimiter: @unchecked Sendable {
    /// 搜索 / 目录 / 正文与 JS 内 `java.ajax` 共用同一份限流状态。
    static let shared = SourceRateLimiter()

    private struct State {
        var windowStart: UInt64
        var count: Int
        var inFlight: Int
    }

    private let lock = NSLock()
    private var states: [String: State] = [:]
    private let now: @Sendable () -> UInt64

    init(now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.now = now
    }

    /// 取得一个请求名额；需要等待时挂起，不阻塞线程。
    func acquire(key: String, rule: SourceRateRule) async {
        while true {
            let wait = step(key: key, rule: rule)
            guard wait > 0 else { return }
            do {
                try await Task.sleep(nanoseconds: wait)
            } catch {
                // 任务取消：让上层看到取消，而不是无限重试。
                return
            }
        }
    }

    /// 归还名额。窗口模式不需要归还，多次调用无副作用。
    func release(key: String, rule: SourceRateRule) {
        guard !rule.isWindowed else { return }
        lock.lock()
        if var state = states[key] {
            state.inFlight = max(0, state.inFlight - 1)
            states[key] = state
        }
        lock.unlock()
    }

    /// 返回 0 表示放行，否则返回需要等待的纳秒数。
    private func step(key: String, rule: SourceRateRule) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let current = now()
        var state = states[key] ?? State(windowStart: current, count: 0, inFlight: 0)
        let elapsed = current >= state.windowStart ? current - state.windowStart : 0

        if rule.isWindowed {
            if state.count == 0 || elapsed >= rule.windowNanoseconds {
                state.windowStart = current
                state.count = 1
                states[key] = state
                return 0
            }
            if state.count < rule.limit {
                state.count += 1
                states[key] = state
                return 0
            }
            states[key] = state
            return max(rule.windowNanoseconds - elapsed, 1_000_000)
        }

        if state.inFlight > 0 {
            states[key] = state
            return rule.windowNanoseconds
        }
        if state.count > 0, elapsed < rule.windowNanoseconds {
            states[key] = state
            return max(rule.windowNanoseconds - elapsed, 1_000_000)
        }
        state.windowStart = current
        state.count = 1
        state.inFlight = 1
        states[key] = state
        return 0
    }
}