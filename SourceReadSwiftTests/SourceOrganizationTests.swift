import XCTest
@testable import SourceReadSwift

final class SourceOrganizationTests: XCTestCase {
    private func source(_ id: String, group: String? = nil, enabled: Bool = true, weight: Int = 0) -> BookSource {
        BookSource(bookSourceName: id, bookSourceUrl: "https://\(id).test", bookSourceGroup: group,
                   enabled: enabled, weight: weight)
    }

    func testPinsAlwaysBracketEverySortMode() {
        let sources = [source("a", weight: 100), source("b"), source("c", enabled: false)]
        for sort in SourceLibrarySort.allCases {
            var preferences = SourceOrganization()
            preferences.sort = sort
            preferences.placements = [sources[0].id: .bottom, sources[2].id: .top]
            XCTAssertEqual(preferences.ordered(sources).map(\.bookSourceName), ["c", "b", "a"])
        }
    }

    func testFilteredDragPreservesHiddenSlotsAndPinPlacement() {
        let sources = [source("a"), source("b"), source("c"), source("d"), source("e")]
        var preferences = SourceOrganization()
        preferences.placements[sources[0].id] = .top
        preferences.reorder([sources[4].id, sources[2].id, sources[1].id], in: sources)
        XCTAssertEqual(preferences.ordered(sources).map(\.bookSourceName), ["a", "e", "c", "d", "b"])
        XCTAssertEqual(preferences.placements[sources[0].id], .top)
    }

    func testUnknownAndDuplicateDragIDsCannotLoseSources() {
        let sources = [source("a"), source("b"), source("c")]
        var preferences = SourceOrganization()
        preferences.reorder(["missing", sources[2].id, sources[2].id, sources[0].id], in: sources)
        XCTAssertEqual(preferences.ordered(sources).map(\.bookSourceName), ["c", "b", "a"])
        XCTAssertEqual(Set(preferences.order).count, 3)
    }

    func testSortModesAreDeterministicAndCanReturnToManualOrder() {
        let sources = [source("c", enabled: false, weight: 90), source("b", weight: 2), source("a", weight: 10)]
        var preferences = SourceOrganization()
        preferences.reorder(sources.map(\.id), in: sources)
        preferences.sort = .name
        XCTAssertEqual(preferences.ordered(sources).map(\.bookSourceName), ["a", "b", "c"])
        preferences.sort = .enabled
        XCTAssertEqual(preferences.ordered(sources).map(\.bookSourceName), ["b", "a", "c"])
        preferences.sort = .weight
        XCTAssertEqual(preferences.ordered(sources).map(\.bookSourceName), ["c", "a", "b"])
        preferences.sort = .custom
        XCTAssertEqual(preferences.ordered(sources).map(\.bookSourceName), ["c", "b", "a"])
    }

    func testImportedMultiGroupsAndExplicitUngroupedOverride() {
        let source = source("a", group: " 小说, 漫画；小说\n收藏 ")
        var preferences = SourceOrganization()
        XCTAssertEqual(preferences.groups(for: source), ["小说", "漫画", "收藏"])
        preferences.groupOverrides[source.id] = ""
        XCTAssertTrue(preferences.groups(for: source).isEmpty)
        XCTAssertEqual(source.bookSourceGroup, " 小说, 漫画；小说\n收藏 ", "Classification must not rewrite parser/source metadata")
    }

    func testRenameAndDeleteImportedGroupRetainOtherMemberships() {
        let sources = [source("a", group: "小说,收藏"), source("b", group: "小说")]
        var preferences = SourceOrganization()
        preferences.renameGroup("小说", to: "文字", sources: sources)
        XCTAssertEqual(preferences.groups(for: sources[0]), ["文字", "收藏"])
        XCTAssertFalse(preferences.allGroups(in: sources).contains("小说"))
        preferences.deleteGroup("文字", sources: sources)
        XCTAssertEqual(preferences.groups(for: sources[0]), ["收藏"])
        XCTAssertTrue(preferences.groups(for: sources[1]).isEmpty)
    }

    func testLegacySnapshotHasDefaultOrganization() throws {
        let data = Data(#"{"sources":[],"rssSources":[],"catalogs":[]}"#.utf8)
        let restored = try JSONDecoder().decode(SourceLibrarySnapshot.self, from: data)
        XCTAssertEqual(restored.organization, SourceOrganization())
    }

    @MainActor func testDeletingSourceAlsoForgetsOnlyItsOrganization() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SourceStore(persistence: SourcePersistence(rootURL: root))
        let sources = [source("a"), source("b")]
        try store.importSources(sources)
        store.setPlacement(.top, for: Set(sources.map(\.id)))
        store.setGroup("收藏", for: Set(sources.map(\.id)))
        store.remove(sources[0])
        XCTAssertNil(store.organization.placements[sources[0].id])
        XCTAssertNil(store.organization.groupOverrides[sources[0].id])
        XCTAssertEqual(store.organization.placements[sources[1].id], .top)
        try store.importSources([sources[0]])
        XCTAssertEqual(store.organization.placement(for: sources[0]), .normal)
    }

    @MainActor func testOrganizationSurvivesRestartReimportAndBackupRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = SourcePersistence(rootURL: root)
        let store = SourceStore(persistence: persistence)
        let sources = [source("a"), source("b"), source("c")]
        try store.importSources(sources)
        store.setPlacement(.top, for: [sources[2].id])
        store.setPlacement(.bottom, for: [sources[0].id])
        store.setGroup("我的收藏", for: [sources[2].id, sources[1].id])
        store.reorderSources([sources[2].id, sources[1].id, sources[0].id])
        let expected = store.organization
        try store.importSources([source("c", group: "新导入分组", weight: 100), source("d")])
        let reopened = SourceStore(persistence: persistence)
        XCTAssertEqual(reopened.organization, expected)
        XCTAssertEqual(reopened.organization.ordered(reopened.sources).map(\.bookSourceName), ["c", "b", "d", "a"])
        let backup = try JSONDecoder().decode(SourceLibrarySnapshot.self, from: JSONEncoder().encode(reopened.backupSnapshot()))
        XCTAssertTrue(store.restore(backup))
        XCTAssertEqual(store.organization, expected)
        XCTAssertEqual(store.organization.groups(for: try XCTUnwrap(store.source(for: sources[2].id))), ["我的收藏"])
    }

    @MainActor func testFailedSaveDoesNotPublishUnsavedOrganization() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SourceStore(persistence: SourcePersistence(rootURL: root))
        let before = store.organization
        let saved = store.updateOrganization { $0.namedGroups = ["不能保存"] }
        XCTAssertFalse(saved)
        XCTAssertEqual(store.organization, before)
        XCTAssertNotNil(store.lastError)
    }
}
