import XCTest
@testable import SourceReadSwift

/// A handful of Legado sources (醉读小说 / 顶点小说) drive their search and
/// chapter HTTP calls through `Packages.okhttp3` instead of `java.ajax`.
/// The stub maps that API onto the same injected network handler so those
/// sources stop falling into their `catch (e) {}` branch on the first line.
final class OkHttp3BridgeTests: XCTestCase {
    func testBuilderBuildsRequestWithUrl() throws {
        let runtime = JSCoreRuntime { url in url }

        let result = runtime.evaluate(
            """
            var request = new Packages.okhttp3.Request.Builder()
              .url('https://example.com/x')
              .build();
            request.url();
            """
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(value, "https://example.com/x")
    }

    func testNewCallExecuteReturnsBody() throws {
        let runtime = JSCoreRuntime { url in
            "ok:\(url)"
        }

        let result = runtime.evaluate(
            """
            var request = new Packages.okhttp3.Request.Builder()
              .url('https://example.com/a')
              .addHeader('X-Test', '1')
              .build();
            var client = new Packages.okhttp3.OkHttpClient();
            client.newCall(request).execute().body().string();
            """
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(value, #"ok:https://example.com/a@Header:{"X-Test":"1"}"#)
    }

    func testPostBuilderForwardsBody() throws {
        let runtime = JSCoreRuntime { url in url }

        let result = runtime.evaluate(
            """
            var request = new Packages.okhttp3.Request.Builder()
              .url('https://example.com/p')
              .post('q=1')
              .build();
            new Packages.okhttp3.OkHttpClient().newCall(request).execute().body().string();
            """
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertTrue(value.contains("@Body:q=1"), "body directive missing: \(value)")
    }
}
