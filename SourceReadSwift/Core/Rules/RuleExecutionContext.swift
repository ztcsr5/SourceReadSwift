import Foundation

/// Mutable state shared by every rule and JavaScript fragment in one source execution.
///
/// JavaScriptCore is thread-confined, but native callbacks may arrive on another queue.
/// Keeping the state behind a lock prevents the bridge from creating a second, divergent
/// variable store (the main compatibility problem of the previous prelude-only runtime).
final class RuleExecutionContext: @unchecked Sendable {
    typealias NetworkHandler = (String) -> String
    typealias ResponseHandler = (String) -> SourceResponse?
    typealias LogHandler = (String) -> Void

    private let lock = NSRecursiveLock()
    private var values: [String: Any] = [:]
    private let persistentState: RulePersistentState
    private var recordedLogs: [String] = []
    private var javascriptEvidence: [SourceJavaScriptEvidence] = []
    private var executionStage: String?
    private var cachedRuntime: JSCoreRuntime?
    private var lastJavaScriptError: String?

    var networkHandler: NetworkHandler?
    var responseHandler: ResponseHandler?
    var logHandler: LogHandler?
    var source: BookSource?
    /// Optional synchronous captcha provider. Production wiring points this
    /// at VerificationCodeCoordinator; tests leave it nil for deterministic runs.
    var verificationCodeProvider: ((String) -> String)?

    /// Most recent JavaScript exception raised while evaluating a rule.
    /// Parsers surface it instead of a bare "0 items" message so a broken
    /// `jsLib` helper is distinguishable from an empty rule match.
    func recordJavaScriptError(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        lastJavaScriptError = trimmed
        lock.unlock()
    }

    var currentJavaScriptError: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastJavaScriptError
    }

    func clearJavaScriptError() {
        lock.lock()
        lastJavaScriptError = nil
        lock.unlock()
    }

    func jsRuntime(ajaxHandler: @escaping (String) -> String) -> JSCoreRuntime {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedRuntime {
            return cached
        }
        let runtime = JSCoreRuntime(ajaxHandler: ajaxHandler, executionContext: self)
        // The runtime installs jsLib after binding source and the first rule's
        // globals. Loading it here freezes an empty source/baseUrl in any
        // library-level initializer, before evaluate can supply real values.
        cachedRuntime = runtime
        return runtime
    }

    func collectGarbage() {
        lock.lock()
        defer { lock.unlock() }
        cachedRuntime?.collectGarbage()
    }

    func resetRuntime() {
        lock.lock()
        defer { lock.unlock() }
        cachedRuntime?.collectGarbage()
        cachedRuntime = nil
    }

    func cleanUp() {
        lock.lock()
        defer { lock.unlock() }
        cachedRuntime?.collectGarbage()
        cachedRuntime = nil
        values.removeAll(keepingCapacity: false)
        recordedLogs.removeAll(keepingCapacity: false)
        javascriptEvidence.removeAll(keepingCapacity: false)
    }

    deinit {
        cleanUp()
    }

    init(
        initialValues: [String: Any] = [:],
        persistentState: RulePersistentState = RulePersistentState(),
        source: BookSource? = nil,
        networkHandler: NetworkHandler? = nil,
        responseHandler: ResponseHandler? = nil,
        logHandler: LogHandler? = nil,
        stage: String? = nil
    ) {
        self.source = source ?? (initialValues["source"] as? BookSource)
        self.networkHandler = networkHandler
        self.responseHandler = responseHandler
        self.logHandler = logHandler
        self.executionStage = stage
        self.persistentState = persistentState
        bind(initialValues)
        if let source {
            bind(["source": source])
        }
    }

    /// The production engine sets this to `search`, `detail`, `toc`, or
    /// `content` before evaluating a rule.  Keeping the marker in the shared
    /// context means a JavaScript exception remains attributable even when a
    /// source uses several nested `@js:`/`bodyJs` fragments.
    func setExecutionStage(_ stage: String?) {
        lock.lock()
        executionStage = stage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        lock.unlock()
    }

    var currentExecutionStage: String? {
        lock.lock()
        defer { lock.unlock() }
        return executionStage
    }

    func bind(_ newValues: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        for (key, value) in newValues {
            values[key] = value
        }
        if newValues["result"] == nil, let html = newValues["html"] {
            values["result"] = html
        }
    }

    func setValue(_ value: Any?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            values[key] = value
            if key == "cookieHeader" {
                persistentState.put(Self.bridgeString(value), for: key)
            }
        } else {
            values.removeValue(forKey: key)
            if key == "cookieHeader" {
                persistentState.remove(key)
            }
        }
    }

    func value(for key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    /// Reads a value that may have been produced by an earlier stage.  The
    /// in-memory dictionary preserves native types; `RulePersistentState`
    /// keeps both the JS-visible string and the original object so native
    /// `@put` values survive a new execution context.
    func storedValue(for key: String) -> Any? {
        lock.lock()
        if let value = values[key] {
            lock.unlock()
            return value
        }
        lock.unlock()
        if let object = persistentState.object(for: key) { return object }
        return persistentState.storedString(for: key)
    }

    func string(for key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let value = values[key] {
            return Self.bridgeString(value)
        }
        return persistentState.get(key)
    }

    @discardableResult
    func put(_ value: Any?, for key: String) -> String {
        let text = Self.bridgeString(value)
        lock.lock()
        values[key] = value ?? ""
        lock.unlock()
        persistentState.put(text, for: key)
        persistentState.putObject(value ?? "", for: key)
        return text
    }

    func get(_ key: String) -> String {
        string(for: key)
    }

    func remove(_ key: String) {
        lock.lock()
        values.removeValue(forKey: key)
        lock.unlock()
        persistentState.remove(key)
    }

    /// Removes every scoped variable sharing a prefix.  Legado sources use
    /// `source.removeLoginInfo()` to clear the `source.login.*` namespace;
    /// without prefix enumeration those credentials survive a re-login.
    func removePrefix(_ prefix: String) {
        guard !prefix.isEmpty else { return }
        lock.lock()
        let keys = values.keys.filter { $0.hasPrefix(prefix) }
        for key in keys { values.removeValue(forKey: key) }
        lock.unlock()
        persistentState.removePrefix(prefix)
    }

    /// Enumerates every variable sharing a prefix.  Legado login maps need
    /// real key enumeration for `isEmpty()` and `Object.keys()`.
    func keys(withPrefix prefix: String) -> [String] {
        guard !prefix.isEmpty else { return [] }
        lock.lock()
        let memoryKeys = values.keys.filter { $0.hasPrefix(prefix) }
        lock.unlock()
        let persistentKeys = persistentState.keys(withPrefix: prefix)
        return Array(Set(memoryKeys).union(persistentKeys)).sorted()
    }

    func persistentSnapshot() -> [String: String] { persistentState.snapshot() }

    /// Merges a per-book variable snapshot captured while the search result
    /// was built.  Values written later (cookies, login tokens) stay intact
    /// because only the keys present in the snapshot are replaced.
    func mergePersistent(_ snapshot: [String: String]) {
        for (key, value) in snapshot {
            persistentState.put(value, for: key)
        }
    }

    /// Import response cookies into the same state used by `java.put/get`.
    /// This mirrors Android's source-scoped cookie jar and deliberately keeps
    /// only cookie names/values in diagnostics; response bodies and secrets are
    /// never logged here.
    func ingestResponse(_ response: SourceResponse) {
        let names = persistentState.ingestResponse(response)
        guard !names.isEmpty else { return }
        setValue(persistentState.get("cookieHeader"), for: "cookieHeader")
        log("response cookies persisted: \(names.joined(separator: ","))")
    }

    func log(_ message: String) {
        lock.lock()
        recordedLogs.append(message)
        lock.unlock()
        logHandler?(message)
    }

    /// Standardized bridge diagnostics are deliberately short and are later
    /// redacted together with JavaScript evidence before export.
    func recordBridgeFailure(_ bridge: String, message: String) {
        log("bridge.error \(bridge): \(message)")
    }

    func logs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLogs
    }

    /// Keep the latest normalized JavaScript fragments for source diagnostics.
    /// The scripts themselves are safe to retain here; redaction happens when
    /// they are copied into an exported diagnostic step.
    func recordJavaScript(_ evidence: SourceJavaScriptEvidence) {
        lock.lock()
        javascriptEvidence.append(evidence)
        if javascriptEvidence.count > 16 { javascriptEvidence.removeFirst(javascriptEvidence.count - 16) }
        lock.unlock()
    }

    func javascriptEvidenceSnapshot() -> [SourceJavaScriptEvidence] {
        lock.lock()
        defer { lock.unlock() }
        return javascriptEvidence
    }

    func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    static func bridgeString(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let value = value as? String { return value }
        if let value = value as? NSString { return value as String }
        if let value = value as? NSNumber { return value.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
}

/// Synchronous, lock-protected storage shared by all JS contexts used for one
/// source.  Legado sources commonly `java.put` a nonce/cookie in search and
/// read it again from detail or content; creating a fresh JS context per stage
/// must not erase those values.
final class RulePersistentState: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var objects: [String: Any] = [:]

    func put(_ value: String, for key: String) {
        lock.lock(); values[key] = value; lock.unlock()
    }

    func get(_ key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return values[key] ?? ""
    }

    /// Native `@put` values keep their original type across stages; the
    /// JS-visible string form remains in `values` for `java.get`.
    func putObject(_ value: Any, for key: String) {
        lock.lock(); objects[key] = value; lock.unlock()
    }

    func object(for key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return objects[key]
    }

    func storedString(for key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func remove(_ key: String) {
        lock.lock()
        values.removeValue(forKey: key)
        objects.removeValue(forKey: key)
        lock.unlock()
    }

    func removePrefix(_ prefix: String) {
        guard !prefix.isEmpty else { return }
        lock.lock()
        let keys = Set(values.keys.filter { $0.hasPrefix(prefix) })
            .union(objects.keys.filter { $0.hasPrefix(prefix) })
        for key in keys {
            values.removeValue(forKey: key)
            objects.removeValue(forKey: key)
        }
        lock.unlock()
    }

    func keys(withPrefix prefix: String) -> [String] {
        guard !prefix.isEmpty else { return [] }
        lock.lock(); defer { lock.unlock() }
        // `putObject` can be the only writer for a native `@put` value, so a
        // values-only enumeration would hide those keys from
        // `source.getVariable` / `Object.keys` style lookups.
        return Set(values.keys.filter { $0.hasPrefix(prefix) })
            .union(objects.keys.filter { $0.hasPrefix(prefix) })
            .sorted()
    }

    /// String view used for `{{placeholder}}` expansion.  Native objects are
    /// exposed through `object(for:)`; this snapshot stays JSON-friendly.
    func snapshot() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return values
    }

    /// Merge response Set-Cookie values into the source-scoped state and return
    /// only cookie names for diagnostics. Values are intentionally not exposed
    /// in logs.
    @discardableResult
    func ingestResponse(_ response: SourceResponse) -> [String] {
        let values = CookieHeaderParser.setCookieValues(from: response.headers)
            .compactMap { CookieHeaderParser.cookiePair(fromSetCookie: $0) }
        guard !values.isEmpty else { return [] }
        let incoming = values.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        lock.lock()
        let existing = self.values["cookieHeader"] ?? ""
        let merged = CookieHeaderParser.merge(incoming, into: existing.isEmpty ? nil : existing)
        if !merged.isEmpty { self.values["cookieHeader"] = merged }
        lock.unlock()
        return values.map(\.name)
    }
}
