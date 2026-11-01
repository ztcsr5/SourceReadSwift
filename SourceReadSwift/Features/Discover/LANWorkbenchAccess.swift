import Foundation

/// The public landing page contains no credential. A new capability is shown
/// only on the phone on each start and never accepted in URLs or cookies.
final class LANWorkbenchAccess {
    private let lock = NSLock()
    private var token = ""

    func renew() -> String {
        lock.lock(); defer { lock.unlock() }
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return token
    }

    func revoke() {
        lock.lock(); defer { lock.unlock() }
        token = ""
    }

    func permits(_ request: LightweightHTTPRequest) -> Bool {
        guard request.method != "OPTIONS", Self.isSameOrigin(request) else { return false }
        lock.lock(); defer { lock.unlock() }
        let supplied = Array((request.headers["x-sourceread-token"] ?? "").utf8)
        let expected = Array(token.utf8)
        guard !expected.isEmpty, supplied.count == expected.count else { return false }
        return zip(supplied, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func isSameOrigin(_ request: LightweightHTTPRequest) -> Bool {
        if request.headers["sec-fetch-site"]?.lowercased() == "cross-site" { return false }
        // Native CLI clients have no Origin. Browser clients must use the
        // current authority; there is deliberately no wildcard CORS grant.
        guard let origin = request.headers["origin"] else { return true }
        guard let host = request.headers["host"],
              let actual = URLComponents(string: origin),
              let target = URLComponents(string: "http://" + host),
              actual.scheme == "http", actual.user == nil, actual.password == nil,
              actual.host?.lowercased() == target.host?.lowercased(),
              (actual.port ?? 80) == (target.port ?? 80),
              actual.path.isEmpty, actual.query == nil, actual.fragment == nil else { return false }
        return true
    }
}
