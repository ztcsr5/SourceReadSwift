import Foundation
import Network

struct SourceProxyConfiguration: Equatable, Sendable {
    enum ProtocolKind: String, Hashable, Sendable { case http, socks5 }

    var isEnabled: Bool
    var host: String
    var port: Int
    var protocolKind: ProtocolKind

    enum ValidationError: LocalizedError {
        case host, port

        var errorDescription: String? {
            switch self {
            case .host: return "输入主机名、IPv4 或 IPv6 地址，不要包含协议、路径或端口。"
            case .port: return "输入 1 到 65535 之间的端口。"
            }
        }
    }

    /// Resolves a form draft without changing the active network session.
    static func validate(host: String, port: String, protocolKind: ProtocolKind) throws -> Self {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = trimmed.hasPrefix("[") && trimmed.hasSuffix("]") ? String(trimmed.dropFirst().dropLast()) : trimmed
        guard isValidHost(address), (!trimmed.hasPrefix("[") || IPv6Address(address) != nil) else {
            throw ValidationError.host
        }
        let portText = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !portText.isEmpty, portText.utf8.count <= 5,
              portText.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(portText), (1...65_535).contains(number) else { throw ValidationError.port }
        return Self(isEnabled: true, host: address, port: number, protocolKind: protocolKind)
    }

    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        if IPv4Address(host) != nil || IPv6Address(host) != nil { return true }
        if host.contains("."), host.utf8.allSatisfy({ $0 == 46 || (48...57).contains($0) }) { return false }
        let name = host.hasSuffix(".") ? host.dropLast() : host[...]
        guard !name.isEmpty else { return false }
        return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard !label.isEmpty, label.utf8.count <= 63, label.first != "-", label.last != "-" else { return false }
            return label.utf8.allSatisfy { $0 == 45 || (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
        }
    }

    var connectionProxyDictionary: [AnyHashable: Any]? {
        guard isEnabled else { return nil }
        switch protocolKind {
        case .socks5:
            return ["SOCKSEnable": 1, "SOCKSProxy": host, "SOCKSPort": port, "SOCKSVersion": "5"]
        case .http:
            return ["HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
                    "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port]
        }
    }

    private static let storageKey = "source_proxy_configuration"

    /// Read one committed snapshot, falling back to settings stored by older versions.
    static func load(from defaults: UserDefaults) -> Self {
        if let saved = defaults.dictionary(forKey: storageKey),
           let enabled = saved["enabled"] as? Bool, let host = saved["host"] as? String,
           let port = saved["port"] as? Int, let raw = saved["protocol"] as? String,
           let kind = ProtocolKind(rawValue: raw) {
            return Self(isEnabled: enabled, host: host, port: port, protocolKind: kind)
        }
        let legacyPort = defaults.integer(forKey: "source_proxy_port")
        return Self(isEnabled: defaults.bool(forKey: "source_proxy_enabled"),
                    host: defaults.string(forKey: "source_proxy_host") ?? "127.0.0.1",
                    port: legacyPort > 0 ? legacyPort : 7890,
                    protocolKind: ProtocolKind(rawValue: defaults.string(forKey: "source_proxy_type") ?? "") ?? .http)
    }

    func store(in defaults: UserDefaults) {
        defaults.set(["enabled": isEnabled, "host": host, "port": port,
                      "protocol": protocolKind.rawValue] as [String: Any], forKey: Self.storageKey)
    }
}

/// Commits proxy changes once, leaving open requests on their existing session.
@MainActor
final class SourceProxyManager: ObservableObject {
    static let shared = SourceProxyManager()

    @Published private(set) var configuration: SourceProxyConfiguration
    private let defaults: UserDefaults
    private let resetSession: () -> Void

    var isEnabled: Bool { configuration.isEnabled }
    var host: String { configuration.host }
    var port: Int { configuration.port }

    init(defaults: UserDefaults = .standard, resetSession: @escaping () -> Void = URLSessionSourceNetworkClient.resetSession) {
        self.defaults = defaults
        self.resetSession = resetSession
        self.configuration = SourceProxyConfiguration.load(from: defaults)
    }

    func save(isEnabled: Bool, host: String, port: String, protocolKind: SourceProxyConfiguration.ProtocolKind) throws {
        var updated = configuration
        if isEnabled { updated = try SourceProxyConfiguration.validate(host: host, port: port, protocolKind: protocolKind) }
        else { updated.isEnabled = false }
        guard updated != configuration else { return }
        updated.store(in: defaults)
        resetSession()
        configuration = updated
    }
}
