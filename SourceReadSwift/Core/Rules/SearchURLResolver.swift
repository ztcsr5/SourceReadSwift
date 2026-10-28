import Foundation

struct SearchURLResolver {
    private let ruleResolver = LegadoRuleResolver()

    func resolve(
        source: BookSource,
        keyword: String,
        page: Int,
        persistentState: RulePersistentState = RulePersistentState(),
        network: SourceNetworkClient? = nil,
        executionContext: RuleExecutionContext? = nil
    ) -> Result<String, SourceEngineError> {
        guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else {
            return .failure(.invalidSource("searchUrl \u{4e3a}\u{7a7a}"))
        }

        let sourceInterpolated = interpolateSourcePlaceholders(searchUrl, source: source)
        var cleaned = sourceInterpolated
        if cleaned.contains("{{cookie.") {
            cleaned = cleaned.replacingOccurrences(
                of: #"\{\{cookie\.[^}]*\}\}"#,
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let searchCharset = Self.charset(searchUrl: searchUrl, source: source)
        let scriptVariables = scriptVariables(source: source, keyword: keyword, page: page)
        let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        func postProcess(_ result: String) -> String {
            let expanded = LegadoRuleResolver.replacePageAngles(in: result, page: page)
            let (urlPart, suffixPart) = Self.splitURLAndDirectiveSuffix(expanded)
            // A `@js:` rule (e.g. 曼哈漫画) can build the query with its own
            // `{{...}}` placeholders *after* the script returns.  Legado runs
            // `replaceKeyPageJs()` on the evaluated string as well, so the
            // braces must be expanded here instead of being percent-encoded
            // into `%7B%7B...%7D%7D`.
            var evaluatedURLPart = urlPart
            if evaluatedURLPart.contains("{{"), evaluatedURLPart.contains("}}") {
                evaluatedURLPart = resolveEmbeddedBracesScripts(
                    evaluatedURLPart,
                    source: source,
                    variables: scriptVariables,
                    persistentState: persistentState,
                    network: network,
                    executionContext: executionContext
                )
            }
            let interpolatedURL = ruleResolver.interpolate(
                evaluatedURLPart,
                keyword: keyword,
                page: page,
                baseUrl: source.bookSourceUrl,
                charset: searchCharset
            )
            let safeURL = urlSafeString(normalizePathDoubleSlashes(interpolatedURL))
            guard !suffixPart.isEmpty else {
                return safeURL
            }
            let interpolatedSuffix: String
            if Self.isJSONBodyOption(suffixPart) {
                let pageAndBaseInterpolated = ruleResolver.interpolate(
                    suffixPart,
                    keyword: nil,
                    page: page,
                    baseUrl: source.bookSourceUrl,
                    charset: searchCharset
                )
                interpolatedSuffix = pageAndBaseInterpolated
                    .replacingOccurrences(of: "{{key}}", with: keyword)
                    .replacingOccurrences(of: "{{keyword}}", with: keyword)
                    .replacingOccurrences(of: "{{searchKey}}", with: keyword)
                    .replacingOccurrences(of: "{key}", with: keyword)
                    .replacingOccurrences(of: "{keyword}", with: keyword)
                    .replacingOccurrences(of: "{searchKey}", with: keyword)
            } else {
                interpolatedSuffix = ruleResolver.interpolate(
                    suffixPart,
                    keyword: keyword,
                    page: page,
                    baseUrl: source.bookSourceUrl,
                    charset: searchCharset
                )
            }
            return safeURL + interpolatedSuffix
        }

        if trimmedCleaned.hasPrefix("@js:") {
            let script = String(trimmedCleaned.dropFirst(4))
            // Legado binds the rule text being analysed to `result` before
            // it evaluates `@js:`.  Sources rewrite the URL with
            // `result.replace(...)`; without the binding the script throws a
            // ReferenceError and the search dies before any request is sent.
            var variables = scriptVariables
            variables["result"] = cleaned
            let evalResult = evaluateScript(script, source: source, variables: variables, persistentState: persistentState, network: network, executionContext: executionContext)
            return evalResult.map(postProcess)
        }

        if trimmedCleaned.hasPrefix("<js>"), trimmedCleaned.hasSuffix("</js>") {
            let script = String(trimmedCleaned.dropFirst(4).dropLast(5))
            var variables = scriptVariables
            variables["result"] = cleaned
            let evalResult = evaluateScript(script, source: source, variables: variables, persistentState: persistentState, network: network, executionContext: executionContext)
            return evalResult.map(postProcess)
        }

        // A trailing `@js:` after the URL (or after a `,{...}` POST option) is
        // evaluated by Legado before the URL is split from its directives.
        // `result` is the text before the marker, so a source can rewrite the
        // body or the query and hand the new string back.  Without this branch
        // the marker was percent-encoded into the query and every 猫耳 /
        // 随心看吧 style source searched for the literal JS text.
        if let jsRange = cleaned.range(of: "@js:", options: .caseInsensitive) {
            let prefix = String(cleaned[..<jsRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let script = String(cleaned[jsRange.upperBound...])
            if !prefix.isEmpty,
               !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var variables = scriptVariables
                variables["result"] = prefix
                let evalResult = evaluateScript(
                    script,
                    source: source,
                    variables: variables,
                    persistentState: persistentState,
                    network: network,
                    executionContext: executionContext
                )
                return evalResult.map(postProcess)
            }
        }

        var resolvedCleaned = LegadoRuleResolver.replacePageAngles(in: cleaned, page: page)
        if resolvedCleaned.contains("{{") && resolvedCleaned.contains("}}") {
            resolvedCleaned = resolveEmbeddedBracesScripts(
                resolvedCleaned,
                source: source,
                variables: scriptVariables,
                persistentState: persistentState,
                network: network,
                executionContext: executionContext
            )
        }

        let interpolated = postProcess(resolvedCleaned)
        let trimmed = interpolated.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("<js>"), trimmed.contains("</js>") {
            return resolveEmbeddedScripts(
                trimmed,
                source: source,
                variables: scriptVariables,
                persistentState: persistentState,
                network: network,
                executionContext: executionContext
            ).map(postProcess)
        }

        return .success(trimmed)
    }

    static func splitURLAndDirectiveSuffix(_ text: String) -> (urlPart: String, suffixPart: String) {
        var earliestBound: String.Index?

        if let jsonOptionRange = text.range(of: #",\s*\{[\s\S]*$"#, options: .regularExpression) {
            earliestBound = jsonOptionRange.lowerBound
        }

        let directiveMarkers = [
            "@Header:", "@Headers:", "@Body:", "@Post:",
            "@RequestBody:", "@Charset:", "@Encoding:"
        ]
        for marker in directiveMarkers {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                if let current = earliestBound {
                    if range.lowerBound < current {
                        earliestBound = range.lowerBound
                    }
                } else {
                    earliestBound = range.lowerBound
                }
            }
        }

        guard let bound = earliestBound else {
            return (text, "")
        }
        return (String(text[..<bound]), String(text[bound...]))
    }

    static func isJSONBodyOption(_ optionText: String) -> Bool {
        if optionText.localizedCaseInsensitiveContains("application/json") {
            return true
        }
        if optionText.contains("\\\"") {
            return true
        }
        if optionText.contains("\"keyword\"") || optionText.contains("\"key\"") {
            return true
        }
        if optionText.range(
            of: #"(?:["']?(?:body|requestBody|postBody|data)["']?\s*:\s*(?:\{|\[|["']\s*[\{\[]))"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        if optionText.range(
            of: #"@(?:Body|Post|RequestBody):\s*[\{\[]"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        return false
    }

    /// 把插值后仍可能带空格 / 中文 / 裸花括号的纯 URL 部分修成 `URL(string:)` 能吃的形态。
    ///
    /// 仅对纯 URL 部分调用（绝不触碰 `,{"method":...}` 或 `@Header:{...}` 指令后缀），
    /// 并保留已有的 `%[0-9A-Fa-f]{2}` 转义序列，杜绝二次编码为 `%25`。
    private func urlSafeString(_ raw: String) -> String {
        if raw.contains("<js>"), raw.contains("</js>") {
            return raw
        }
        return SourceRequestBuilder.percentEncodePreservingExistingEscapes(raw)
    }

    private func normalizePathDoubleSlashes(_ urlString: String) -> String {
        guard let schemeRange = urlString.range(of: "^https?://", options: .regularExpression) else {
            return urlString
        }
        let afterScheme = urlString[schemeRange.upperBound...]
        guard let slashIndex = afterScheme.firstIndex(of: "/") else {
            return urlString
        }
        let prefix = String(urlString[..<slashIndex])
        let pathAndBeyond = String(urlString[slashIndex...])
        let queryOrHashIdx = pathAndBeyond.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? pathAndBeyond.endIndex
        let pathPart = String(pathAndBeyond[..<queryOrHashIdx])
        let suffix = String(pathAndBeyond[queryOrHashIdx...])
        let collapsedPath = pathPart.replacingOccurrences(of: "/{2,}", with: "/", options: .regularExpression)
        return prefix + collapsedPath + suffix
    }

    private func resolveEmbeddedScripts(
        _ text: String,
        source: BookSource,
        variables: [String: Any],
        persistentState: RulePersistentState,
        network: SourceNetworkClient?,
        executionContext: RuleExecutionContext?
    ) -> Result<String, SourceEngineError> {
        var output = text
        while let startRange = output.range(of: "<js>"),
              let endRange = output.range(of: "</js>", range: startRange.upperBound..<output.endIndex) {
            let script = String(output[startRange.upperBound..<endRange.lowerBound])
            switch evaluateScript(script, source: source, variables: variables, persistentState: persistentState, network: network, executionContext: executionContext) {
            case .success(let value):
                output.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: value)
            case .failure(let error):
                return .failure(error)
            }
        }
        return .success(output)
    }

    private func resolveEmbeddedBracesScripts(
        _ text: String,
        source: BookSource,
        variables: [String: Any],
        persistentState: RulePersistentState,
        network: SourceNetworkClient?,
        executionContext: RuleExecutionContext?
    ) -> String {
        var output = text
        var searchStart = output.startIndex

        while let open = output.range(of: "{{", range: searchStart..<output.endIndex) {
            // Legado scans `{{ ... }}` with a balanced scan, not a regex: a
            // JavaScript block may legally contain object literals (`{}`) and
            // `${...}` template holes. The old `(?:[^{}]|(?!\}\}))+` pattern
            // matched a zero-width alternative on `{`, so a multi-line block
            // (抖音小说) never matched and stayed as `%7B%7B...`.
            var depth = 0
            var cursor = open.lowerBound
            var closeStart: String.Index?
            while cursor < output.endIndex {
                let ch = output[cursor]
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        closeStart = output.index(cursor, offsetBy: -1)
                        break
                    }
                }
                cursor = output.index(after: cursor)
            }
            guard let close = closeStart else { break }

            let innerRange = open.upperBound..<close
            let fullRange = open.lowerBound..<output.index(after: cursor)
            let expr = String(output[innerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = expr.lowercased()
            let isPlaceholder = lower == "key" || lower == "keyword" || lower == "searchkey"
                || lower == "page" || lower == "baseurl" || lower == "booksourceurl"
                || lower.hasPrefix("page+") || lower.hasPrefix("page-")
                || lower.hasPrefix("page*") || lower.hasPrefix("page/")
            if isPlaceholder {
                searchStart = fullRange.upperBound
                continue
            }

            let evalResult = evaluateScript(
                expr,
                source: source,
                variables: variables,
                persistentState: persistentState,
                network: network,
                executionContext: executionContext
            )
            let replacement: String
            switch evalResult {
            case .success(let val):
                let trimmedVal = val.trimmingCharacters(in: .whitespacesAndNewlines)
                // A multi-line `{{ ... }}` block returns its last expression,
                // exactly like Legado's `eval`. Treating every block that
                // contains `;` as side-effect-only dropped the computed URL.
                if trimmedVal == "undefined" || trimmedVal == "null" || trimmedVal.isEmpty
                    || trimmedVal == "true" || trimmedVal == "false" {
                    replacement = ""
                } else {
                    replacement = val
                }
            case .failure:
                replacement = ""
            }
            output.replaceSubrange(fullRange, with: replacement)
            searchStart = output.startIndex
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func evaluateScript(
        _ script: String,
        source: BookSource,
        variables: [String: Any],
        persistentState: RulePersistentState,
        network: SourceNetworkClient?,
        executionContext: RuleExecutionContext?
    ) -> Result<String, SourceEngineError> {
        let runtime = makeRuntime(source: source, persistentState: persistentState, network: network, executionContext: executionContext)
        let direct = runtime.evaluate(script, variables: variables)
        if case .failure(.javascript) = direct, script.contains("return") {
            return runtime.evaluate("(function(){\(script)})()", variables: variables)
        }
        return direct
    }

    private func makeRuntime(source: BookSource, persistentState: RulePersistentState, network: SourceNetworkClient?, executionContext sharedContext: RuleExecutionContext? = nil) -> JSCoreRuntime {
        let context = sharedContext ?? RuleExecutionContext(
            initialValues: ["source": source, "baseUrl": source.bookSourceUrl],
            persistentState: persistentState,
            source: source,
            networkHandler: { urlText in
                if let network {
                    return SynchronousSourceNetworkBridge.loadBody(
                        urlText: urlText,
                        source: source,
                        network: network,
                        cookieHeader: persistentState.get("cookieHeader").nilIfEmpty,
                        persistentValues: persistentState.snapshot(),
                        persistentState: persistentState
                    )
                }
                return SynchronousSourceLoader().load(
                    urlText: urlText,
                    source: source,
                    cookieHeader: persistentState.get("cookieHeader").nilIfEmpty,
                    persistentValues: persistentState.snapshot(),
                    persistentState: persistentState
                )
            },
            responseHandler: { urlText in
                if let network {
                    return SynchronousSourceNetworkBridge.loadResponse(
                        urlText: urlText,
                        source: source,
                        network: network,
                        cookieHeader: persistentState.get("cookieHeader").nilIfEmpty,
                        persistentValues: persistentState.snapshot(),
                        persistentState: persistentState
                    )
                }
                return SynchronousSourceLoader().loadResponse(
                    urlText: urlText,
                    source: source,
                    cookieHeader: persistentState.get("cookieHeader").nilIfEmpty,
                    persistentValues: persistentState.snapshot(),
                    persistentState: persistentState
                )
            }
        )
        if context.source == nil {
            context.source = source
        }
        let runtime = context.jsRuntime(ajaxHandler: { urlText in
            if let network {
                return SynchronousSourceNetworkBridge.loadBody(
                    urlText: urlText,
                    source: source,
                    network: network,
                    cookieHeader: persistentState.get("cookieHeader").nilIfEmpty,
                    persistentValues: persistentState.snapshot(),
                    persistentState: persistentState
                )
            }
            return SynchronousSourceLoader().load(
                urlText: urlText,
                source: source,
                cookieHeader: persistentState.get("cookieHeader").nilIfEmpty,
                persistentValues: persistentState.snapshot(),
                persistentState: persistentState
            )
        })
        if let jsLib = source.raw["jsLib"], !jsLib.isEmpty {
            _ = runtime.evaluate(jsLib)
        }
        return runtime
    }

    private func interpolateSourcePlaceholders(_ text: String, source: BookSource) -> String {
        let baseReplaced = LegadoRuleResolver.replaceBaseUrlPlaceholders(in: text, baseUrl: source.bookSourceUrl)
        let baseKeys: Set<String> = ["bookSourceUrl", "sourceUrl", "cleanSourceUrl", "baseUrl"]
        return sourceVariableMap(source: source).reduce(baseReplaced) { output, item in
            guard !baseKeys.contains(item.key) else { return output }
            return output
                .replacingOccurrences(of: "{{source.\(item.key)}}", with: item.value)
                .replacingOccurrences(of: "{source.\(item.key)}", with: item.value)
                .replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
                .replacingOccurrences(of: "{\(item.key)}", with: item.value)
        }
    }

    private func scriptVariables(source: BookSource, keyword: String, page: Int) -> [String: Any] {
        let sourceMap = sourceVariableMap(source: source) as NSDictionary
        return [
            "keyword": keyword,
            "key": keyword,
            "page": page,
            "baseUrl": source.cleanSourceURL,
            "source": sourceMap
        ]
    }

    private func sourceVariableMap(source: BookSource) -> [String: String] {
        var values = source.raw
        let cleanBase = source.cleanSourceURL
        values["bookSourceName"] = source.bookSourceName
        values["sourceName"] = source.bookSourceName
        values["bookSourceUrl"] = source.bookSourceUrl
        values["sourceUrl"] = cleanBase
        values["cleanSourceUrl"] = cleanBase
        values["baseUrl"] = cleanBase
        values["bookSourceGroup"] = source.bookSourceGroup ?? ""
        values["sourceGroup"] = source.bookSourceGroup ?? ""
        values["bookSourceType"] = String(source.bookSourceType)
        values["weight"] = String(source.weight)
        values["searchUrl"] = source.searchUrl ?? ""
        values["exploreUrl"] = source.exploreUrl ?? ""
        values["header"] = source.header ?? ""
        values["customConfig"] = source.customConfig ?? ""
        return values
    }

    /// Effective charset for the search keyword.
    ///
    /// Android Legado reads `charset` from the URL option JSON (AnalyzeUrl.kt
    /// L186) and passes it to `analyzeFields`, where `"escape"` switches to
    /// `EncoderUtils.escape`.  Falling back to the GBK heuristic keeps every
    /// source that never declared a charset working as before.
    static func charset(searchUrl: String, source: BookSource) -> String? {
        let (_, suffixPart) = splitURLAndDirectiveSuffix(searchUrl)
        if !suffixPart.isEmpty,
           let brace = suffixPart.range(of: "{"),
           let data = String(suffixPart[brace.lowerBound...]).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["charset", "encoding", "encode"] {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return isGBKEncoding(searchUrl: searchUrl, source: source) ? "gbk" : nil
    }

    static func isGBKEncoding(searchUrl: String, source: BookSource) -> Bool {
        let combined = [
            searchUrl,
            source.bookSourceUrl,
            source.header,
            source.customConfig,
            source.ruleSearch?.raw,
            source.ruleSearch?.fields["charset"],
            source.raw["charset"],
            source.raw["encoding"],
            source.raw["bookSourceComment"],
            source.raw["comment"]
        ].compactMap { $0 }.joined(separator: " ").lowercased()

        return combined.contains("gbk")
            || combined.contains("gb2312")
            || combined.contains("gb18030")
            || combined.contains("cp936")
    }
}
