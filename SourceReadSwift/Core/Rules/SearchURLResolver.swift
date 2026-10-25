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
        let isGBK = Self.isGBKEncoding(searchUrl: searchUrl, source: source)
        let scriptVariables = scriptVariables(source: source, keyword: keyword, page: page)
        let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        func postProcess(_ result: String) -> String {
            let interpolated = ruleResolver.interpolate(
                result,
                keyword: keyword,
                page: page,
                baseUrl: source.cleanSourceURL,
                charset: isGBK ? "gbk" : nil
            )
            return urlSafeString(normalizePathDoubleSlashes(interpolated))
        }

        if trimmedCleaned.hasPrefix("@js:") {
            let script = String(trimmedCleaned.dropFirst(4))
            let evalResult = evaluateScript(script, source: source, variables: scriptVariables, persistentState: persistentState, network: network, executionContext: executionContext)
            return evalResult.map(postProcess)
        }

        if trimmedCleaned.hasPrefix("<js>"), trimmedCleaned.hasSuffix("</js>") {
            let script = String(trimmedCleaned.dropFirst(4).dropLast(5))
            let evalResult = evaluateScript(script, source: source, variables: scriptVariables, persistentState: persistentState, network: network, executionContext: executionContext)
            return evalResult.map(postProcess)
        }

        var resolvedCleaned = cleaned
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

        return .success(urlSafeString(normalizePathDoubleSlashes(trimmed)))
    }

    /// 把插值后仍可能带空格 / 中文 / 裸花括号的 URL 修成 `URL(string:)` 能吃的形态。
    ///
    /// 诊断数据里 991 个源有 31 条倒在 `URL 格式非法或解析异常 (-1000)`：
    /// 多数是 `searchUrl` 里 `{{key}}` 拼进中文关键词、或模板里留了空格/花括号，
    /// 解析器直接拿到一个非法字符串。这里只在**确实解析不了**时逐个字符转义，
    /// 已经合法的 URL 原样返回，不会把 `%XX` 二次编码。
    private func urlSafeString(_ raw: String) -> String {
        if URL(string: raw) != nil { return raw }
        var output = ""
        output.reserveCapacity(raw.count + 16)
        for scalar in raw.unicodeScalars {
            let text = String(scalar)
            if scalar.isASCII, !" \"<>\\^`{|}\n\r\t".unicodeScalars.contains(scalar) {
                output += text
            } else {
                // 空允许集：除 A-Za-z0-9-._~ 外全部百分号编码。
                output += text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "")) ?? text
            }
        }
        return output
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
        let pattern = #"\{\{((?:[^{}]|(?!\}\}))+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return output }

        var searchRange = NSRange(output.startIndex..<output.endIndex, in: output)
        while let match = regex.firstMatch(in: output, range: searchRange) {
            guard let fullRange = Range(match.range, in: output),
                  let innerRange = Range(match.range(at: 1), in: output) else { break }
            let expr = String(output[innerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = expr.lowercased()
            if lower == "key" || lower == "keyword" || lower == "page" || lower == "baseurl"
                || lower.hasPrefix("page+") || lower.hasPrefix("page-") || lower.hasPrefix("page*") || lower.hasPrefix("page/") {
                let nextStart = fullRange.upperBound
                if nextStart < output.endIndex {
                    searchRange = NSRange(nextStart..<output.endIndex, in: output)
                    continue
                } else {
                    break
                }
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
                if trimmedVal == "undefined" || trimmedVal == "null" || trimmedVal == "true" || trimmedVal == "false" || expr.contains(";") || expr.contains("=") {
                    replacement = ""
                } else {
                    replacement = val
                }
            case .failure:
                replacement = ""
            }
            output.replaceSubrange(fullRange, with: replacement)
            searchRange = NSRange(output.startIndex..<output.endIndex, in: output)
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
        sourceVariableMap(source: source).reduce(text) { output, item in
            output
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
