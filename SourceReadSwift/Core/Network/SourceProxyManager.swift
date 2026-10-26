import Foundation

/// 书源请求代理管理器
/// 支持 HTTP/HTTPS 与 SOCKS5 代理分流，适配本地翻墙/抓包客户端（Clash/Surge/Shadowrocket 等）
@MainActor
final class SourceProxyManager: ObservableObject {
    static let shared = SourceProxyManager()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "source_proxy_enabled")
            URLSessionSourceNetworkClient.resetSession()
        }
    }
    @Published var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: "source_proxy_host")
            if isEnabled { URLSessionSourceNetworkClient.resetSession() }
        }
    }
    @Published var port: Int {
        didSet {
            UserDefaults.standard.set(port, forKey: "source_proxy_port")
            if isEnabled { URLSessionSourceNetworkClient.resetSession() }
        }
    }
    @Published var proxyType: String {
        didSet {
            UserDefaults.standard.set(proxyType, forKey: "source_proxy_type")
            if isEnabled { URLSessionSourceNetworkClient.resetSession() }
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "source_proxy_enabled")
        self.host = UserDefaults.standard.string(forKey: "source_proxy_host") ?? "127.0.0.1"
        let savedPort = UserDefaults.standard.integer(forKey: "source_proxy_port")
        self.port = savedPort > 0 ? savedPort : 7890
        self.proxyType = UserDefaults.standard.string(forKey: "source_proxy_type") ?? "http"
    }

    nonisolated func applyProxy(to configuration: URLSessionConfiguration) {
        let enabled = UserDefaults.standard.bool(forKey: "source_proxy_enabled")
        guard enabled else {
            configuration.connectionProxyDictionary = nil
            return
        }
        let host = UserDefaults.standard.string(forKey: "source_proxy_host") ?? "127.0.0.1"
        let port = UserDefaults.standard.integer(forKey: "source_proxy_port")
        let effectivePort = port > 0 ? port : 7890
        let type = UserDefaults.standard.string(forKey: "source_proxy_type") ?? "http"

        var proxyDict: [AnyHashable: Any] = [:]
        if type == "socks5" {
            proxyDict[kCFStreamPropertySOCKSProxy as String] = 1
            proxyDict[kCFStreamPropertySOCKSProxyHost as String] = host
            proxyDict[kCFStreamPropertySOCKSProxyPort as String] = effectivePort
        } else {
            proxyDict[kCFNetworkProxiesHTTPEnable as String] = 1
            proxyDict[kCFNetworkProxiesHTTPProxy as String] = host
            proxyDict[kCFNetworkProxiesHTTPPort as String] = effectivePort
            proxyDict[kCFNetworkProxiesHTTPSEnable as String] = 1
            proxyDict[kCFNetworkProxiesHTTPSProxy as String] = host
            proxyDict[kCFNetworkProxiesHTTPSPort as String] = effectivePort
        }
        configuration.connectionProxyDictionary = proxyDict
    }
}
