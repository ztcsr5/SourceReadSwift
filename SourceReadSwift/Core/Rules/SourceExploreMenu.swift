import Foundation

/// Source-defined discovery controls, separate from navigable category links.
struct SourceExploreControl: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case button, text, select }
    let id: String
    let title: String
    let kind: Kind
    let action: String
    let defaultValue: String
    let choices: [String]
}

struct SourceExploreMenu: Sendable {
    let categories: [ExploreCategory]
    let controls: [SourceExploreControl]
    var message: String? = nil
}

struct SourceExploreActionResult: Sendable {
    let menu: SourceExploreMenu?
    let searchKeyword: String?
    let message: String?
    var destination: SourceLoginDestination? = nil
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
            // Actionless buttons are status labels rather than executable controls.
            guard kind == .text || !action.isEmpty else { return nil }
            var seenChoices = Set<String>()
            let choices = (row["chars"] as? [String] ?? []).filter { !$0.isEmpty && seenChoices.insert($0).inserted }
            guard kind != .select || !choices.isEmpty else { return nil }
            return SourceExploreControl(id: "\(index)|\(title)", title: title, kind: kind,
                action: action, defaultValue: row["default"] as? String ?? "", choices: choices)
        }
        let labels = categories.isEmpty ? rows.compactMap { row -> String? in
            guard (row["url"] as? String ?? "").isEmpty,
                  row["type"] == nil || row["type"] as? String == "button",
                  (row["action"] as? String ?? "").isEmpty,
                  let title = row["title"] as? String else { return nil }
            return title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }.filter { $0 != "--" } : []
        return SourceExploreMenu(categories: categories, controls: controls,
            message: labels.isEmpty ? nil : labels.prefix(3).joined(separator: "\n"))
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
          const outcome = {keyword:null,message:null};
          const originalOpen = java.startBrowser;
          const originalWait = java.startBrowserAwait;
          const originalSearch = java.searchBook;
          const originalRefresh = java.refreshExplore;
          const originalToast = java.toast;
          const originalLongToast = java.longToast;
          java.refreshExplore = function() {};
          java.searchBook = function(keyword) { outcome.keyword = String(keyword || ''); };
          java.toast = java.longToast = function(message) { outcome.message = String(message || ''); };
          java.startBrowser = function(address) {
            if (outcome.address !== undefined) return;
            const url = String(address == null ? '' : address);
            outcome.address = url.length <= 524288 ? url : '';
          };
          java.startBrowserAwait = function() { throw new Error('请从书源账号打开需要网页回调的操作'); };
          try { (function() {
            \(executable)
          })(); }
          finally {
            java.startBrowser = originalOpen; java.startBrowserAwait = originalWait;
            java.searchBook = originalSearch; java.refreshExplore = originalRefresh;
            java.toast = originalToast; java.longToast = originalLongToast;
          }
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
            let message = (outcome["message"] as? String)?.nilIfEmpty
            if outcome["address"] != nil {
                return SourceLoginBrowserAction.destination(from: text).map { destination in
                    SourceExploreActionResult(menu: nil, searchKeyword: nil, message: message, destination: destination)
                }
            }
            return evaluate(source: source, context: context).map {
                SourceExploreActionResult(menu: $0,
                    searchKeyword: (outcome["keyword"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    message: message)
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
