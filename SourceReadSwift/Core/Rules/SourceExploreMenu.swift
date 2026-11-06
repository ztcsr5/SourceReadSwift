import Foundation

/// Source-defined discovery controls, separate from navigable category links.
struct SourceExploreControl: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case button, text }
    let id: String
    let title: String
    let kind: Kind
    let action: String
    let defaultValue: String
}

struct SourceExploreMenu: Sendable {
    let categories: [ExploreCategory]
    let controls: [SourceExploreControl]
}

struct SourceExploreActionResult: Sendable {
    let menu: SourceExploreMenu
    let searchKeyword: String?
    let message: String?
}

enum SourceExploreMenuParser {
    /// Parses the evaluated menu without treating buttons or inputs as group headings.
    static func parse(_ text: String) -> SourceExploreMenu {
        let categories = ExploreCategoryParser.parse(exploreUrl: text)
        guard let bytes = text.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] else {
            return SourceExploreMenu(categories: categories, controls: [])
        }
        let controls = rows.enumerated().compactMap { index, row -> SourceExploreControl? in
            guard let title = row["title"] as? String, !title.isEmpty,
                  let type = row["type"] as? String,
                  let kind = SourceExploreControl.Kind(rawValue: type.lowercased()) else { return nil }
            let action = (row["action"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // An inert button is a status label; the refreshed link title already carries that state.
            guard kind == .text || !action.isEmpty else { return nil }
            return SourceExploreControl(id: "\(index)|\(title)", title: title, kind: kind,
                action: action, defaultValue: row["default"] as? String ?? "")
        }
        return SourceExploreMenu(categories: categories, controls: controls)
    }

    /// Evaluates discovery using the same source state as search, detail and content.
    static func evaluate(source: BookSource, context: RuleExecutionContext) -> Result<SourceExploreMenu, SourceEngineError> {
        let raw = (source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let script = script(from: raw) else { return .success(parse(raw)) }
        return context.jsRuntime(ajaxHandler: { context.networkHandler?($0) ?? "" })
            .evaluate(script, variables: variables(source: source)).map(parse)
    }

    /// Runs one explicit user action and reports its requested refresh/search to the container.
    static func perform(source: BookSource, action: String, inputs: [String: String],
                        context: RuleExecutionContext) -> Result<SourceExploreActionResult, SourceEngineError> {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 256 * 1024 else {
            return .failure(.invalidSource("发现操作为空或超过 256 KiB"))
        }
        guard inputs.count <= 128, inputs.allSatisfy({ $0.key.count <= 256 && $0.value.count <= 4096 }) else {
            return .failure(.invalidSource("发现表单内容过长，请缩短后重试"))
        }
        let executable = script(from: trimmed) ?? trimmed
        let wrapped = """
        (function() {
          var outcome = {keyword:null,message:null};
          java.refreshExplore = function() {};
          java.searchBook = function(keyword) { outcome.keyword = String(keyword || ''); };
          java.toast = function(message) { outcome.message = String(message || ''); };
          (function() { \(executable) })();
          return JSON.stringify(outcome);
        })()
        """
        var bindings = variables(source: source)
        bindings["infoMap"] = inputs
        let runtime = context.jsRuntime(ajaxHandler: { context.networkHandler?($0) ?? "" })
        switch runtime.evaluate(wrapped, variables: bindings) {
        case .failure(let error): return .failure(error)
        case .success(let text):
            guard let bytes = text.data(using: .utf8),
                  let outcome = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                return .failure(.rule("发现操作没有返回有效状态"))
            }
            return evaluate(source: source, context: context).map {
                SourceExploreActionResult(menu: $0,
                    searchKeyword: (outcome["keyword"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    message: (outcome["message"] as? String)?.nilIfEmpty)
            }
        }
    }

    private static func variables(source: BookSource) -> [String: Any] {
        ["source": source, "baseUrl": source.networkBaseURL, "result": "", "key": "", "page": 1]
    }

    private static func script(from raw: String) -> String? {
        if raw.hasPrefix("@js:") { return String(raw.dropFirst(4)) }
        if raw.hasPrefix("<js>"), raw.hasSuffix("</js>") { return String(raw.dropFirst(4).dropLast(5)) }
        return nil
    }
}
