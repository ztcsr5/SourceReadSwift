import XCTest
@testable import SourceReadSwift

final class SourceProxyConfigurationTests: XCTestCase {
    func testValidatesHostAndPortWithoutAcceptingAnEmbeddedURL() throws {
        for host in ["localhost", "reading-proxy.local", "192.168.1.2", "[::1]", "2001:db8::1"] {
            let proxy = try SourceProxyConfiguration.validate(host: " " + host + " ", port: "65535", protocolKind: .socks5)
            XCTAssertEqual(proxy.port, 65_535)
            XCTAssertEqual(proxy.connectionProxyDictionary?["SOCKSProxy"] as? String, proxy.host)
        }
        for host in ["", ".", "https://localhost", "localhost:7890", "localhost/path", "a..b", "x@y", "[localhost]", "999.1.2.3"] {
            XCTAssertThrowsError(try SourceProxyConfiguration.validate(host: host, port: "7890", protocolKind: .http),
                                 "Accepted invalid proxy host: \(host)")
        }
        for port in ["", "0", "-1", "65536", "7,890", "１２"] {
            XCTAssertThrowsError(try SourceProxyConfiguration.validate(host: "localhost", port: port, protocolKind: .http),
                                 "Accepted invalid port: \(port)")
        }
    }

    @MainActor func testRejectedAndUnchangedSavesDoNotResetAnActiveSession() throws {
        let suite = "SourceProxyConfigurationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "source_proxy_enabled")
        defaults.set("legacy.local", forKey: "source_proxy_host")
        defaults.set(1080, forKey: "source_proxy_port")
        defaults.set("socks5", forKey: "source_proxy_type")

        var applied: [SourceProxyConfiguration] = []
        let manager = SourceProxyManager(defaults: defaults, resetSession: {
            applied.append(SourceProxyConfiguration.load(from: defaults))
        })
        XCTAssertEqual(manager.host, "legacy.local")
        XCTAssertEqual(manager.port, 1080)
        XCTAssertEqual(manager.configuration.protocolKind, .socks5)
        XCTAssertThrowsError(try manager.save(isEnabled: true, host: "proxy.local", port: "0", protocolKind: .http))
        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(manager.host, "legacy.local")

        try manager.save(isEnabled: true, host: " proxy.local ", port: "7890", protocolKind: .http)
        XCTAssertEqual(applied, [manager.configuration])
        XCTAssertEqual(applied.first?.connectionProxyDictionary?["HTTPSProxy"] as? String, "proxy.local")
        try manager.save(isEnabled: true, host: "proxy.local", port: "7890", protocolKind: .http)
        XCTAssertEqual(applied.count, 1)

        try manager.save(isEnabled: false, host: "", port: "", protocolKind: .http)
        XCTAssertEqual(applied.count, 2)
        XCTAssertNil(applied.last?.connectionProxyDictionary)
        XCTAssertEqual(SourceProxyConfiguration.load(from: defaults).host, "proxy.local")
    }
}
