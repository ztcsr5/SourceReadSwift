import Foundation
import JavaScriptCore

/// Evaluates source-authored request headers in the existing rule runtime.
enum SourceScriptHeaderResolver {
    private static let evaluationMarker = "__sourceReadHeaderEvaluation"
    private static let libraryMarker = "__sourceReadHeaderLibraryInitialization"
    private static let maximumHeaderBytes = 64 * 1024
    private static let maximumHeaderCount = 128
    private static let scopedBindings = ["src", "result", "html", "content", "id", "type", "source", "baseUrl",
        "book", "chapter", "key", "keyword", "page", JSCoreRuntime.ruleDocumentBinding]

    /// Library bootstrap requests run before the library's header functions are ready.
    static func withLibraryInitialization<Value>(context: RuleExecutionContext, operation: () -> Value) -> Value {
        let previous = context.value(for: libraryMarker)
        context.setValue(true, for: libraryMarker)
        defer { context.setValue(previous, for: libraryMarker) }
        return operation()
    }

    /// Returns nil for static headers or a bootstrap request made by this header itself.
    static func evaluate(source: BookSource, context: RuleExecutionContext) -> Result<[String: String]?, SourceEngineError> {
        guard let script = source.header?.trimmingCharacters(in: .whitespacesAndNewlines),
              script.hasPrefix("@js:") || script.hasPrefix("<js>") else { return .success(nil) }
        // A header may fetch its token with java.ajax. That subrequest keeps
        // explicit/login/cookie headers, but must not evaluate this header again.
        guard context.value(for: evaluationMarker) == nil,
              context.value(for: libraryMarker) == nil else { return .success(nil) }
        context.setValue(true, for: evaluationMarker)
        defer { context.setValue(nil, for: evaluationMarker) }

        let runtime = context.jsRuntime(ajaxHandler: { [weak context] address in context?.networkHandler?(address) ?? "" })
        let bindings = context.snapshot()
        let scopedKeys = Set(scopedBindings).union(bindings.keys).subtracting([evaluationMarker, libraryMarker])
        let persistentBefore = context.persistentSnapshot()
        let globals = scopedKeys.reduce(into: [String: JSValue]()) { saved, key in
            saved[key] = runtime.context.objectForKeyedSubscript(key)
        }
        let previousStage = context.currentExecutionStage
        let previousFailure = context.latestScriptRequestFailure
        context.setExecutionStage((previousStage.map { $0 + "." } ?? "") + "header")
        context.recordScriptRequestFailure(nil)
        defer {
            let persistentAfter = context.persistentSnapshot()
            for key in scopedKeys {
                if scopedBindings.contains(key) || persistentAfter[key] == persistentBefore[key], let value = globals[key] {
                    runtime.context.setObject(value, forKeyedSubscript: key as NSString)
                }
                if persistentAfter[key] == persistentBefore[key] { context.setValue(bindings[key], for: key) }
            }
            context.setExecutionStage(previousStage)
            if context.latestScriptRequestFailure == nil { context.recordScriptRequestFailure(previousFailure) }
        }

        var variables = bindings
        variables.removeValue(forKey: evaluationMarker)
        variables["source"] = source
        if (variables["baseUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            variables["baseUrl"] = source.cleanSourceURL
        }
        let normalized = JSCoreRuntime.bindingUnderscoreJavaToBridge(LegadoJavaScriptCompatibility.normalizeRuleScript(script))
        guard let encoded = try? JSONSerialization.data(withJSONObject: [normalized]),
              let argument = String(data: encoded, encoding: .utf8) else {
            return .failure(.rule("书源请求头脚本无法编码，未发送请求"))
        }
        // Direct eval keeps its completion value while var/function declarations
        // stay inside this call. The source still receives the global this object.
        let isolatedScript = "(function() { return eval(" + argument + "[0]); }).call(this)"
        switch runtime.evaluate(isolatedScript, variables: variables) {
        case .failure:
            // Source exceptions can contain tokens and addresses. Keep those
            // in the existing private JS evidence, never in the public error.
            return .failure(.javascript("书源请求头脚本执行失败，未发送请求"))
        case .success(let output):
            if let failure = context.latestScriptRequestFailure { return .failure(failure) }
            return parse(output).map { Optional($0) }
        }
    }

    private static func parse(_ output: String) -> Result<[String: String], SourceEngineError> {
        guard output.utf8.count <= maximumHeaderBytes else {
            return .failure(.rule("书源请求头脚本输出超过 64 KiB，未发送请求"))
        }
        guard let encoded = output.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              fields.count <= maximumHeaderCount else {
            return .failure(.rule("书源请求头脚本必须返回最多 128 项的 JSON 对象，未发送请求"))
        }
        var headers: [String: String] = [:]
        var foldedNames: Set<String> = []
        for name in fields.keys.sorted() {
            guard isValidName(name), foldedNames.insert(name.lowercased()).inserted,
                  let value = scalarString(fields[name]), value.utf8.count <= 8192,
                  value.unicodeScalars.allSatisfy({ $0.value == 9 || ($0.value >= 32 && $0.value != 127) }) else {
                return .failure(.rule("书源请求头包含非法名称、重复字段或非标量/超长/控制字符值，未发送请求"))
            }
            headers[name] = value
        }
        return .success(headers)
    }

    private static func scalarString(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 256 else { return false }
        let punctuation = "!#$%&'*+-.^_`|~"
        return name.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value)
                || punctuation.unicodeScalars.contains($0)
        }
    }
}
