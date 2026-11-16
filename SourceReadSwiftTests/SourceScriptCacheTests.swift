import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceScriptCacheTests: XCTestCase {
    private var rootURL: URL!
    private let scope = "https://cache.fixture.invalid/source-a"

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: rootURL.path) { try FileManager.default.removeItem(at: rootURL) }
    }

    func testDeviceRegistrationSurvivesIndependentRuleContexts() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        let register = makeRuntime(store)
        XCTAssertEqual(try register.evaluate("cache.put('device', 'synthetic-device-42')").get(), "synthetic-device-42")
        let request = makeRuntime(store)
        XCTAssertEqual(try request.evaluate("cache.get('device')").get(), "synthetic-device-42")
        XCTAssertEqual(try request.evaluate("java.getCache('device')").get(), "synthetic-device-42")
    }

    func testRuntimeInheritsContextStoreUnlessExplicitlyOverridden() throws {
        let inherited = SourceScriptCacheStore(rootURL: rootURL, isPersistent: false)
        let explicitStore = SourceScriptCacheStore(rootURL: rootURL, isPersistent: false)
        let source = BookSource(bookSourceName: "Synthetic cache fixture", bookSourceUrl: scope)
        let context = RuleExecutionContext(source: source)
        context.scriptCacheStore = inherited
        try inherited.put("inherited", for: "key", scope: scope)
        try explicitStore.put("override", for: "key", scope: scope)
        XCTAssertEqual(try JSCoreRuntime(executionContext: context).evaluate("cache.get('key')").get(), "inherited")
        XCTAssertEqual(try JSCoreRuntime(executionContext: context, scriptCacheStore: explicitStore).evaluate("cache.get('key')").get(), "override")
    }

    func testDurableEntriesSurviveStoreReloadButMemoryDoesNot() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        try store.put("saved-selection", for: "sources", scope: scope)
        try store.putMemory("temporary-counter", for: "counter", scope: scope)
        let reopened = SourceScriptCacheStore(rootURL: rootURL)
        XCTAssertEqual(try reopened.get("sources", scope: scope), "saved-selection")
        XCTAssertNil(try reopened.getFromMemory("counter", scope: scope))
    }

    func testLifetimeUsesSecondsAndExpiresAtExactDeadline() throws {
        var instant = Date(timeIntervalSince1970: 1000)
        let store = SourceScriptCacheStore(rootURL: rootURL, clock: { instant })
        try store.put("temporary", for: "ttl", scope: scope, lifetime: 2)
        try store.put("permanent", for: "forever", scope: scope)
        instant = Date(timeIntervalSince1970: 1001.999)
        XCTAssertEqual(try store.get("ttl", scope: scope), "temporary")
        instant = Date(timeIntervalSince1970: 1002)
        XCTAssertNil(try store.get("ttl", scope: scope))
        XCTAssertEqual(try store.get("forever", scope: scope), "permanent")
        try store.put("already-expired", for: "forever", scope: scope, lifetime: -1)
        XCTAssertNil(try store.get("forever", scope: scope))
        XCTAssertThrowsError(try store.put("invalid", for: "ttl", scope: scope, lifetime: .infinity))
    }

    func testCacheAliasForwardsLifetime() throws {
        var instant = Date(timeIntervalSince1970: 1000)
        let store = SourceScriptCacheStore(rootURL: rootURL, clock: { instant })
        let runtime = makeRuntime(store)
        XCTAssertEqual(try runtime.evaluate("cache.putInCache('alias', 'value', 1)").get(), "value")
        instant = Date(timeIntervalSince1970: 1001)
        XCTAssertEqual(try runtime.evaluate("cache.getFromCache('alias')").get(), "")
    }

    func testMemoryObjectsCrossRuntimesAndRemainSeparateFromDisk() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        let first = makeRuntime(store)
        _ = try first.evaluate("cache.put('shared-key','durable'); cache.putMemory('shared-key',{count:2, templates:['a']}); 'done'").get()
        let second = makeRuntime(store)
        XCTAssertEqual(try second.evaluate("JSON.stringify(cache.getFromMemory('shared-key'))").get(), #"{"count":2,"templates":["a"]}"#)
        _ = try second.evaluate("cache.deleteMemory('shared-key')").get()
        XCTAssertEqual(try second.evaluate("cache.get('shared-key')").get(), "durable")
        XCTAssertEqual(try second.evaluate("cache.getFromMemory('shared-key')").get(), "")
    }

    func testDeleteRemovesBothContainersAndReturnsOldDurableValue() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        let runtime = makeRuntime(store)
        _ = try runtime.evaluate("cache.put('key','disk'); cache.putMemory('key','memory'); 'done'").get()
        XCTAssertEqual(try runtime.evaluate("cache.remove('key')").get(), "disk")
        XCTAssertEqual(try runtime.evaluate("cache.get('key') + '|' + cache.getFromMemory('key')").get(), "|")
        XCTAssertNil(try SourceScriptCacheStore(rootURL: rootURL).get("key", scope: scope))
    }

    func testSourceIsolationAndUnscopedRuntimeIsolation() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        _ = try makeRuntime(store).evaluate("cache.put('sources','source-a'); cache.putMemory('same','a'); 'done'").get()
        let other = makeRuntime(store, sourceURL: "https://cache.fixture.invalid/source-b")
        XCTAssertEqual(try other.evaluate("cache.get('sources') + '|' + cache.getFromMemory('same')").get(), "|")
        let folder = rootURL.appendingPathComponent("source-script-cache-v1")
        let persistedFiles = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let unscoped = JSCoreRuntime(scriptCacheStore: store)
        _ = try unscoped.evaluate("cache.put('anonymous','private-runtime'); cache.putMemory('memory','private-runtime')").get()
        XCTAssertEqual(try JSCoreRuntime(scriptCacheStore: store).evaluate("cache.get('anonymous') + '|' + cache.getFromMemory('memory')").get(), "|")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), persistedFiles)
    }

    func testTransientStoreNeverCreatesFiles() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL, isPersistent: false)
        try store.put("process-only", for: "anonymous", scope: scope)
        XCTAssertEqual(try store.get("anonymous", scope: scope), "process-only")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: rootURL.path).isEmpty)
        try store.delete("anonymous", scope: scope)
        XCTAssertNil(try store.get("anonymous", scope: scope))
    }

    func testCacheKeysAreHashedAndOverlongKeysAreRejected() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        try store.put("synthetic", for: "../../session?key=fixture", scope: scope)
        let folder = rootURL.appendingPathComponent("source-script-cache-v1")
        let filename = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: folder.path).first)
        XCTAssertEqual(filename.count, 69)
        XCTAssertTrue(filename.dropLast(5).allSatisfy { $0.isHexDigit })
        XCTAssertThrowsError(try store.put("synthetic", for: String(repeating: "k", count: 4097), scope: scope))
        XCTAssertEqual(try store.get("../../session?key=fixture", scope: scope), "synthetic")
    }

    func testPersistentEntryLimitEvictsLeastRecentlyUsed() throws {
        var limits = SourceScriptCacheStore.Limits()
        limits.maximumDiskEntries = 2
        var instant = Date(timeIntervalSince1970: 1000)
        let store = SourceScriptCacheStore(rootURL: rootURL, limits: limits, clock: { instant })
        try store.put("a", for: "a", scope: scope)
        instant.addTimeInterval(1)
        try store.put("b", for: "b", scope: scope)
        instant.addTimeInterval(1)
        XCTAssertEqual(try store.get("a", scope: scope), "a")
        instant.addTimeInterval(1)
        try store.put("c", for: "c", scope: scope)
        XCTAssertNil(try store.get("b", scope: scope))
        XCTAssertEqual(try store.get("a", scope: scope), "a")
        XCTAssertEqual(try store.get("c", scope: scope), "c")
        XCTAssertNil(try SourceScriptCacheStore(rootURL: rootURL, limits: limits).get("b", scope: scope))
    }

    func testMemoryBudgetEvictsLeastRecentlyUsedAndRejectsOversize() throws {
        var limits = SourceScriptCacheStore.Limits()
        limits.maximumMemoryBytes = 6
        var instant = Date(timeIntervalSince1970: 1000)
        let store = SourceScriptCacheStore(rootURL: rootURL, limits: limits, clock: { instant })
        try store.putMemory("aaa", for: "a", scope: scope)
        instant.addTimeInterval(1)
        try store.putMemory("bbb", for: "b", scope: scope)
        instant.addTimeInterval(1)
        XCTAssertEqual(try store.getFromMemory("a", scope: scope), "aaa")
        instant.addTimeInterval(1)
        try store.putMemory("ccc", for: "c", scope: scope)
        XCTAssertNil(try store.getFromMemory("b", scope: scope))
        XCTAssertEqual(try store.getFromMemory("a", scope: scope), "aaa")
        XCTAssertThrowsError(try store.putMemory("1234567", for: "a", scope: scope))
        XCTAssertEqual(try store.getFromMemory("a", scope: scope), "aaa")
    }

    func testFrozenClockStillMaintainsDiskAndMemoryAccessOrder() throws {
        var limits = SourceScriptCacheStore.Limits()
        limits.maximumDiskEntries = 2
        limits.maximumMemoryEntries = 2
        let store = SourceScriptCacheStore(rootURL: rootURL, limits: limits, clock: { Date(timeIntervalSince1970: 1000) })
        try store.put("a", for: "a", scope: scope)
        try store.put("b", for: "b", scope: scope)
        XCTAssertEqual(try store.get("a", scope: scope), "a")
        try store.put("c", for: "c", scope: scope)
        XCTAssertNil(try store.get("b", scope: scope))
        XCTAssertEqual(try store.get("a", scope: scope), "a")
        try store.putMemory("a", for: "a", scope: scope)
        try store.putMemory("b", for: "b", scope: scope)
        XCTAssertEqual(try store.getFromMemory("a", scope: scope), "a")
        try store.putMemory("c", for: "c", scope: scope)
        XCTAssertNil(try store.getFromMemory("b", scope: scope))
        XCTAssertEqual(try store.getFromMemory("a", scope: scope), "a")
    }

    func testExpiredEntriesAreRemovedBeforeEvictingLiveEntriesAfterReload() throws {
        var limits = SourceScriptCacheStore.Limits()
        limits.maximumDiskEntries = 2
        var instant = Date(timeIntervalSince1970: 1000)
        let store = SourceScriptCacheStore(rootURL: rootURL, limits: limits, clock: { instant })
        try store.put("live", for: "live", scope: scope)
        instant.addTimeInterval(1)
        try store.put("expired", for: "expired", scope: scope, lifetime: 1)
        instant.addTimeInterval(1)
        let reopened = SourceScriptCacheStore(rootURL: rootURL, limits: limits, clock: { instant })
        try reopened.put("new", for: "new", scope: scope)
        XCTAssertEqual(try reopened.get("live", scope: scope), "live")
        XCTAssertNil(try reopened.get("expired", scope: scope))
        XCTAssertEqual(try reopened.get("new", scope: scope), "new")
    }

    func testDeletingAnExternallyRemovedEntryRemainsIdempotent() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        try store.put("value", for: "key", scope: scope)
        let folder = rootURL.appendingPathComponent("source-script-cache-v1")
        let entryURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let uncached = SourceScriptCacheStore(rootURL: rootURL)
        XCTAssertNil(try uncached.get("missing", scope: scope))
        try FileManager.default.removeItem(at: entryURL)
        XCTAssertNil(try uncached.get("key", scope: scope))
        try store.delete("key", scope: scope)
        XCTAssertNil(try store.get("key", scope: scope))
        try store.delete("key", scope: scope)
    }

    func testOversizeWriteDoesNotReplaceValidValueOrNotifyLoginHook() throws {
        var limits = SourceScriptCacheStore.Limits()
        limits.maximumValueBytes = 16
        let store = SourceScriptCacheStore(rootURL: rootURL, limits: limits)
        let runtime = makeRuntime(store)
        let result = try runtime.evaluate("""
        var cacheWrites = 0;
        __sourceReadLoginCacheWritten = function() { cacheWrites++; };
        cache.put('key', 'original');
        try { cache.put('key', '01234567890123456'); } catch (e) {}
        cacheWrites + '|' + cache.get('key');
        """).get()
        XCTAssertEqual(result, "1|original")
    }

    func testDiskByteBudgetBoundsFilesOnDisk() throws {
        var limits = SourceScriptCacheStore.Limits()
        limits.maximumDiskBytes = 200
        let store = SourceScriptCacheStore(rootURL: rootURL, limits: limits)
        for index in 0..<8 { try store.put(String(repeating: "x", count: 80), for: "key-\(index)", scope: scope) }
        let folder = rootURL.appendingPathComponent("source-script-cache-v1")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        let total = try files.reduce(0) { total, url in
            total + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertLessThanOrEqual(total, limits.maximumDiskBytes)
        XCTAssertEqual(try store.get("key-7", scope: scope), String(repeating: "x", count: 80))
    }

    func testStorageFailureThrowsInsteadOfAcknowledgingWrite() throws {
        let obstruction = rootURL.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: obstruction)
        let store = SourceScriptCacheStore(rootURL: obstruction)
        let runtime = makeRuntime(store)
        let result = try runtime.evaluate("""
        var notified = false;
        __sourceReadLoginCacheWritten = function() { notified = true; };
        var failure = '';
        try { cache.put('session', 'synthetic-value'); } catch (e) { failure = e.message; }
        failure + '|' + notified;
        """).get()
        XCTAssertEqual(result, "cache-storage-operation-failed|false")
        try store.putMemory("still-available", for: "memory", scope: scope)
        XCTAssertEqual(try store.getFromMemory("memory", scope: scope), "still-available")
    }

    func testWriteFailureAfterLoadingCatalogPreservesPreviousValueWithoutHook() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        try store.put("original", for: "key", scope: scope)
        let folder = rootURL.appendingPathComponent("source-script-cache-v1")
        try FileManager.default.moveItem(at: folder, to: rootURL.appendingPathComponent("saved-cache"))
        try Data("obstruction".utf8).write(to: folder)
        let runtime = makeRuntime(store)
        let result = try runtime.evaluate("""
        var notified = false;
        __sourceReadLoginCacheWritten = function() { notified = true; };
        var failure = '';
        try { cache.put('key', 'replacement'); } catch (e) { failure = e.message; }
        failure + '|' + notified + '|' + cache.get('key');
        """).get()
        XCTAssertEqual(result, "cache-storage-operation-failed|false|original")
    }

    func testCorruptEntryIsReportedAndRemovedWithoutExposingItsContent() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        try store.put("synthetic", for: "key", scope: scope)
        let folder = rootURL.appendingPathComponent("source-script-cache-v1")
        let entryURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        try Data("broken-json".utf8).write(to: entryURL)
        let reopened = SourceScriptCacheStore(rootURL: rootURL)
        XCTAssertThrowsError(try reopened.get("key", scope: scope)) { error in
            XCTAssertEqual(error as? SourceScriptCacheStore.Failure, .corruptEntry)
        }
        XCTAssertNil(try reopened.get("key", scope: scope))
    }

    func testDeleteClearsMemoryAndNotifiesHookEvenWhenDiskEntryIsCorrupt() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        try store.put("synthetic", for: "key", scope: scope)
        let folder = rootURL.appendingPathComponent("source-script-cache-v1")
        let entryURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        try Data("broken-json".utf8).write(to: entryURL)
        let runtime = makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        let result = try runtime.evaluate("""
        var cacheDeletes = 0;
        __sourceReadLoginCacheWritten = function(key, value) { if (key === 'key' && value === null) cacheDeletes++; };
        cache.putMemory('key', 'memory');
        cache.delete('key') + '|' + cache.getFromMemory('key') + '|' + cacheDeletes;
        """).get()
        XCTAssertEqual(result, "||1")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    func testConcurrentIndependentKeysRemainReadableAfterReload() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        let failures = ScriptCacheFailures()
        let sourceScope = scope
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            do { try store.put("value-\(index)", for: "key-\(index)", scope: sourceScope) }
            catch { failures.record() }
        }
        XCTAssertEqual(failures.count, 0)
        let reopened = SourceScriptCacheStore(rootURL: rootURL)
        for index in 0..<32 { XCTAssertEqual(try reopened.get("key-\(index)", scope: scope), "value-\(index)") }
    }

    private func makeRuntime(_ store: SourceScriptCacheStore, sourceURL: String? = nil) -> JSCoreRuntime {
        let source = BookSource(bookSourceName: "Synthetic cache fixture", bookSourceUrl: sourceURL ?? scope)
        return JSCoreRuntime(executionContext: RuleExecutionContext(source: source), scriptCacheStore: store)
    }
}

private final class ScriptCacheFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var failures = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return failures }
    func record() { lock.lock(); defer { lock.unlock() }; failures += 1 }
}
