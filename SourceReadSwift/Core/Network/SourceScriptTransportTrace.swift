import Foundation

/// Describes a script exchange without recording addresses, headers, or payload values.
enum SourceScriptTransportTrace {
    private static let maximumInspectableBodyBytes = 16 * 1024
    private static let versionFields: Set<String> = ["version", "ver", "versioncode", "sourceversion"]

    static func describe(_ request: SourceRequest, _ result: Result<SourceResponse, SourceEngineError>?) -> String {
        let version = versionPresence(in: request)
        let account = hasHeader("Authorization", in: request)
        let session = hasHeader("Cookie", in: request)
        let requestShape = "\(request.method.rawValue); requestBytes=\(request.body?.count ?? 0); versionField=\(version); authHeader=\(account); sessionHeader=\(session)"
        switch result {
        case .some(.success(let response)):
            let format = bodyShape(response.body)
            return "JS subrequest: \(requestShape); HTTP \(response.statusCode); response=\(format); responseBytes=\(response.data.count)"
        case .some(.failure(_)):
            return "JS subrequest: \(requestShape); no HTTP response"
        case nil:
            return "JS subrequest: \(requestShape); timeout"
        }
    }

    private static func hasHeader(_ name: String, in request: SourceRequest) -> Bool {
        request.headers.contains { key, value in
            key.caseInsensitiveCompare(name) == .orderedSame && !value.isEmpty
        }
    }

    private static func versionPresence(in request: SourceRequest) -> String {
        let url = request.url
        let canInspectQuery = url.absoluteString.utf8.count <= maximumInspectableBodyBytes
        let noMatch = canInspectQuery ? "not-detected" : "not-inspected"
        if canInspectQuery,
           URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: {
               versionFields.contains($0.name.lowercased())
           }) == true { return "present" }
        guard let body = request.body, !body.isEmpty else { return noMatch }
        guard body.count <= maximumInspectableBodyBytes else { return "not-inspected" }
        if let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            return json.keys.contains { versionFields.contains($0.lowercased()) } ? "present" : noMatch
        }
        let isForm = request.headers.contains { key, value in
            key.caseInsensitiveCompare("Content-Type") == .orderedSame
                && value.lowercased().contains("application/x-www-form-urlencoded")
        }
        guard isForm, let form = String(data: body, encoding: .utf8) else { return "not-inspected" }
        let matches = form.split(separator: "&").contains { pair in
            guard let name = pair.split(separator: "=", maxSplits: 1).first else { return false }
            return versionFields.contains(name.lowercased())
        }
        return matches ? "present" : noMatch
    }

    private static func bodyShape(_ body: String) -> String {
        let prefix = body.prefix(128).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if body.isEmpty { return "empty" }
        if prefix.hasPrefix("{") || prefix.hasPrefix("[") { return "json-like" }
        if prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html") { return "html" }
        if prefix.hasPrefix("<") { return "markup" }
        return "text"
    }
}
