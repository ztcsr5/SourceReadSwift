# Comic image Cookie boundary · 2026-11-17

Baseline: `e0d7bbdc`. Native execution is pending; Windows has neither `swiftc` nor Xcode. No failing or passing XCTest run is claimed here.

## Evidence and choice

`RemoteImageLoader.boundedSession` uses `URLSessionConfiguration.default`. `ComicImageTransport` copies that configuration and previously left each request's automatic Cookie handling enabled. The source-owned image header builder can correctly omit Cookie after logout while Foundation adds an older shared Cookie again at the network boundary.

Apple documents that [default configurations share Cookie storage](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpcookiestorage), [automatic outgoing Cookies are enabled by default](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/httpshouldsetcookies), and [URLRequest.httpShouldHandleCookies controls automatic sending and setting](https://developer.apple.com/documentation/foundation/urlrequest/httpshouldhandlecookies). The explicit Cookie behavior is also documented on [NSMutableURLRequest](https://developer.apple.com/documentation/foundation/nsmutableurlrequest/httpshouldhandlecookies). Local API precedents are `AIChatClient.request` and `URLSessionSourceNetworkClient.load`.

The candidate change disables automatic Cookie handling on each comic request only. Source/session/page Cookie headers remain explicit input. Ordinary cover/image session defaults, source parsers and the source Cookie store are unchanged.

## Native reproduction and limits

`ComicImageCookieBoundaryTests` uses a real finite HTTP server bound to `127.0.0.1`. Unique Cookie paths/names isolate fixtures; cleanup removes only fixture cookies. Foundation control requests must prove the server accepts/sends valid automatic cookies before production boundary expectations can pass.

The four cases verify ambient-cookie exclusion, explicit source/page/empty Cookie behavior, separate engines plus logout, and response cookies not entering the shared jar. They exercise actual URLSession sockets rather than URLProtocol replacements. Run on macOS:

```sh
xcodebuild -project SourceReadSwift.xcodeproj -scheme SourceReadSwift -destination 'id=<SIMULATOR_UDID>' -only-testing:SourceReadSwiftTests/ComicImageCookieBoundaryTests -only-testing:SourceReadSwiftTests/RemoteComicImageTests test
```

First run with the two new automatic-Cookie lines removed should demonstrate the baseline failures; then restore the candidate and rerun the same cases. Both executions remain required evidence.

An image server that establishes a new session solely through image-response Set-Cookie is not verified by this change. Such cookies currently have no engine-scoped response callback; preserving that behavior safely needs a separate scoped response-cookie design. The shared Foundation jar is not a source isolation mechanism. Per-image nonce/signature behavior is likewise not covered.
