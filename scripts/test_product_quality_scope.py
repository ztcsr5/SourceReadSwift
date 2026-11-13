"""Run SourceRead product-quality source contracts on a host without the iOS SDK.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_product_quality_scope.py
Use SOURCEREAD_SCOPE_REV to compare the same checks against a committed revision.
"""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = "SourceReadSwift/"
READER = APP + "Features/Reader/ReaderView.swift"
READER_WEB = APP + "Features/Reader/WebScrollReaderView.swift"
SHELF = APP + "Features/Bookshelf/"
DETAIL = APP + "Features/Discover/BookDetailView.swift"


def read_source(path):
    revision = os.environ.get("SOURCEREAD_SCOPE_REV")
    if revision:
        return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT).decode()
    return (ROOT / path).read_text(encoding="utf8")


class ProductQualityScopeTests(unittest.TestCase):
    def test_cbz_import_uses_atomic_files_and_the_comic_route_not_the_novel_surface(self):
        parser = read_source(APP + "Core/Import/LocalComicBookParser.swift")
        self.assertIn("guard checksum == entry.checksum", parser)
        self.assertIn("entry.type != .symlink", parser)
        self.assertIn("FileManager.default.moveItem(at: staging, to: destination)", parser)
        self.assertIn("guard paths.count <= 600", parser)
        gateway = read_source(SHELF + "BookshelfReaderGatewayView.swift")
        self.assertLess(gateway.index('book.sourceURL == "local://comic"'),
                        gateway.index("else if !localBookChapters.isEmpty"))
        self.assertIn("LocalComicSourceEngine(book: currentBook)", gateway)
        project = read_source("project.yml")
        self.assertIn("UTTypeIdentifier: com.edc21.sourceread.cbz", project)
        library = read_source(SHELF + "BookshelfView.swift")
        self.assertIn("bookImportTask?.cancel()", library)
        self.assertIn("onCancel: { parserTask.cancel() }", library)

    def test_preview_membership_acknowledges_disk_writes_and_resume_ignores_temporary_top(self):
        detail = read_source(DETAIL)
        addition = detail.split("private func addCurrentBookToShelf()", 1)[1].split(
            "private func recordPreviewPosition", 1)[0]
        self.assertIn("appState.finishReadingWritesInBackground()", addition)
        self.assertLess(addition.index("await appState.bookshelfStore.waitForPendingWrites()"),
                        addition.index("isSavingShelfPosition = false"))
        comic = read_source(APP + "Features/Reader/ComicReaderView.swift")
        position = comic.split("onPosition: { anchor, isSettled in", 1)[1].split(")", 1)[0]
        self.assertLess(position.index("guard resumeTarget == nil"),
                        position.index("viewportPosition.anchor = anchor"))

    def test_shelf_reader_returns_through_the_route_owner_after_child_presentations(self):
        gateway = read_source(SHELF + "BookshelfReaderGatewayView.swift")
        self.assertEqual(gateway.count("onRequestExit: requestGatewayExit"), 5)
        route = gateway.split("private func requestGatewayExit()", 1)[1].split("    private ", 1)[0]
        self.assertIn("if let onRequestExit", route)
        self.assertIn("dismiss()", route)

    def test_startup_evidence_requires_explicit_regression_mode_and_has_no_prose_or_url(self):
        web = read_source(APP + "Features/Reader/WebScrollReaderView.swift")
        snapshot = web.split("private func recordStartupEvidence(", 1)[1].split("#endif", 1)[0]
        fixtures = web.split("private static let recordsStartupEvidence =", 1)[1].split("#endif", 1)[0]
        self.assertIn('ProcessInfo.processInfo.arguments.contains("--floating-desk-regression")', fixtures)
        self.assertIn('ProcessInfo.processInfo.arguments.contains("--reader-settings-regression")', fixtures)
        self.assertIn("guard Self.recordsStartupEvidence else { return }", snapshot)
        for forbidden in ["textContent", "innerHTML", "location.href", "absoluteString", "CADisplayLink", "Timer"]:
            self.assertNotIn(forbidden, snapshot)
        probe = web.split("private func verifyStartupBridge(", 1)[1].split("private func recordStartupEvidence(", 1)[0]
        self.assertIn("guard !hasReportedPosition else { return }", probe)
        self.assertIn("#if DEBUG", probe)

    def test_native_more_menu_consumes_its_dismissal_without_toggling_the_prose_overlay(self):
        reader = read_source(READER)
        button = read_source(APP + "Features/Reader/ReaderNativeMenuButton.swift")
        tap = reader.split("private func handleReaderTap(", 1)[1].split("private func runTapAction", 1)[0]
        self.assertIn("!nativeMoreMenuPresentation.isActive", tap)
        self.assertLess(tap.index("nativeMoreMenuPresentation.isActive"), tap.index("tapCooldownUntil"))
        self.assertIn("presentation: nativeMoreMenuPresentation", reader)
        self.assertIn("willDisplayMenuFor configuration", button)
        self.assertIn("willEndFor configuration", button)
        self.assertIn("animator.addCompletion(finish)", button)

    def test_comic_streaming_playlists_are_classified_before_generic_rule_parsing(self):
        parser = read_source(APP + "Core/Rules/ContentParser.swift")
        header = "if source.sourceKind == .comic, Self.isStreamingPlaylist("
        self.assertIn(header, parser)
        self.assertLess(parser.index(header), parser.index("let contentRuleStr"))
        self.assertIn("return .failure(.unsupported(", parser[parser.index(header):parser.index("let contentRuleStr")])
        self.assertIn('body.hasPrefix("#EXTM3U', parser)

    def test_startup_fault_is_installed_before_the_first_navigation(self):
        web = read_source(APP + "Features/Reader/WebScrollReaderView.swift")
        creation = web.split("func makeWebView(", 1)[1].split("func tearDown(", 1)[0]
        self.assertLess(creation.index("prepareBeforeNavigation?(webView)"),
                        creation.index("navigateToShell(webView: webView)"))
        navigation = web.split("private func navigateToShell(", 1)[1].split("private func scheduleStartupProbe", 1)[0]
        self.assertLess(navigation.index("navigationToken ="), navigation.index("webView.loadHTMLString("))
        self.assertIn("WebReaderHTML.renderShell(for: navigationID)", navigation)
        fixture = read_source("SourceReadSwiftTests/ReaderModePositionRegressionTests.swift")
        self.assertIn("makeWebView(initialView: fixture, prepareBeforeNavigation:", fixture)
        for original in ["XCTAssertEqual(fault.injections, 1)", "XCTAssertEqual(coordinator.startupRecoveryCount, 1)",
                         "XCTAssertGreaterThan(offset, 500)", "XCTAssertLessThanOrEqual(offset, 600"]:
            self.assertIn(original, fixture)

    def test_late_shell_readiness_cannot_invalidate_already_mounted_prose(self):
        web = read_source(APP + "Features/Reader/WebScrollReaderView.swift")
        ready = web.split('case "ready":', 1)[1].split('case "content-ready":', 1)[0]
        for reset in ["isDocumentReady = false", "mountedContent = nil", "expectedContentRevision ="]:
            self.assertNotIn(reset, ready)
        messages = web.split("func userContentController(", 1)[1].split('case "ready":', 1)[0]
        self.assertIn('body["navigationToken"] as? String == navigationToken', messages)
        probe = web.split("private func verifyStartupBridge(", 1)[1].split("private func recordStartupEvidence(", 1)[0]
        self.assertIn("self.navigationToken == navigationToken", probe)
        fixture = read_source("SourceReadSwiftTests/ReaderModePositionRegressionTests.swift")
        self.assertIn("testLateReadyFromTheMountedShellDoesNotInvalidateItsFirstVisiblePosition", fixture)
        self.assertIn('XCTAssertEqual(bridge.mountedRevisions.count, 1', fixture)

    def test_mode_switch_saves_resolved_chapter_and_local_paragraph(self):
        mode = read_source(READER).split(".onChange(of: readerModeRawValue)", 1)[1].split(
            ".onChange(of: fontFamilyRawValue)", 1)[0]
        self.assertIn("visibleParagraphIndex = paragraph", mode)
        self.assertIn("positionPersistScheduler.cancel()", mode)
        self.assertIn("persistReadingPosition()", mode)
        self.assertNotIn("paragraphIndexOverride:", mode)
        self.assertIn("utf16Offset: anchor?.paragraphUTF16Offset", mode)

    def test_delayed_save_does_not_pair_an_old_paragraph_with_a_new_chapter(self):
        reader = read_source(READER)
        declaration = reader.split("private func scheduleReadingPositionPersistence(", 1)[1].split(
            "private func checkDailyReadingGoal", 1)[0]
        self.assertTrue(declaration.startswith(")"))
        self.assertNotRegex(reader, r"scheduleReadingPositionPersistence\(\s*paragraphIndex:")
        self.assertIn("persistReadingPosition()", declaration)
        self.assertIn("positionPersistScheduler.schedule(", declaration)
        scheduler = reader.split("final class ReaderPositionPersistScheduler", 1)[1]
        self.assertIn("guard !Task.isCancelled", scheduler)

    def test_native_destination_waits_for_positioned_content_without_a_reveal_timer(self):
        host = read_source(APP + "Features/Reader/Navigation/ReaderNavigationHost.swift")
        shelf = read_source(SHELF + "BookshelfView.swift")
        self.assertIn(r".environment(\.readerOpeningManaged, !isReady)", host)
        self.assertIn("onPreferenceChange(ReaderOpeningReadyKey.self)", host)
        self.assertNotIn("Task.sleep", host)
        self.assertNotIn("asyncAfter", host)
        self.assertIn('readerNavigation.open(.shelf(book, sourceID: "continue|" + book.id))', shelf)
        self.assertNotIn("ReaderOpeningPage(", read_source(READER))

    def test_desk_keeps_the_large_cover_envelope_guard(self):
        desk = read_source(SHELF + "FloatingReadingDesk.swift")
        envelope = desk.split("stageEnvelopeHeight: CGFloat = ", 1)[1].splitlines()[0]
        self.assertLessEqual(int(envelope), 220)
        self.assertIn("ReadingDeskTitleTypography.font(size: titleFontSize)", desk)
        self.assertIn(".lineLimit(2)", desk)
        self.assertIn("}.frame(height: Self.stageEnvelopeHeight)", desk)

    def test_desk_restores_native_hold_management_and_keeps_direct_reading(self):
        shelf = read_source(SHELF + "BookshelfView.swift")
        card = shelf.split("private func heroCard", 1)[1].split("private func updateRow", 1)[0]
        self.assertIn('readerNavigation.open(.shelf(book, sourceID: "continue|" + book.id))', card)
        self.assertIn(".contextMenu", card)
        self.assertNotIn(".onLongPressGesture", card)
        self.assertIn("readingDeskEntry(book)", card)
        self.assertNotIn("readingDeskMenu(book)", card)
        self.assertEqual(card.count("readingDeskBookActions(book)"), 1)
        self.assertIn(".contextMenu", shelf.split("private func updateRow", 1)[1])
        self.assertIn('.detail(book, placement: "continue")', shelf)

    def test_detail_keeps_cache_actions_without_a_block_over_the_directory(self):
        detail = read_source(DETAIL)
        self.assertNotIn(".hideRootTabBar()", detail)
        self.assertIn("chapterDownloadMenu", detail)
        self.assertIn("downloadChapters(limit: 50)", detail)
        self.assertIn("downloadChapters(limit: nil)", detail)
        self.assertNotIn("private var downloadSection", detail)
        self.assertNotRegex(detail, r"case \.text:\s*break\b")

    def test_shell_retains_tabs_and_limits_hiding_to_readers(self):
        shell = read_source(APP + "App/RootTabView.swift")
        self.assertEqual(shell.count("TabView(selection: $selectedTab)"), 2)
        self.assertNotIn("ReaderOverlayLayer(", shell)
        self.assertEqual(shell.count(".modifier(RootTabChromeVisibilityModifier())"), 3)
        visibility = shell.split("struct RootTabChromeVisibilityModifier", 1)[1].split("struct HideRootTabBarModifier", 1)[0]
        self.assertIn("content.toolbar(.hidden, for: .tabBar)", visibility)
        self.assertNotIn(".visible", visibility)
        self.assertIn("if !appState.isTabChromeHidden", shell)
        self.assertIn("LegacyTabBar(selection: $selectedTab)", shell)
        self.assertNotIn("switch selectedTab", shell)
        self.assertIn(".safeAreaInset(edge: .bottom, spacing: 0)", shell)
        for path in ("Features/Settings/SettingsView.swift", "Features/SourceManager/SourceManagerView.swift"):
            self.assertNotIn(".hideRootTabBar()", read_source(APP + path))
        self.assertIn(".toolbar(.hidden, for: .navigationBar, .tabBar)", read_source(READER))

    def test_loading_error_does_not_reveal_or_write_unpositioned_prose(self):
        reader = read_source(READER)
        waiting = reader.split(".task(id: openingPositionAttempt)", 1)[1].split(".onPreferenceChange", 1)[0]
        self.assertIn("hasOpeningPositionTimedOut = true", waiting)
        self.assertNotIn("resolveOpeningPreview()", waiting)
        self.assertIn("guard didLandInitialPosition", reader)
        self.assertIn("!readerOpeningManaged || hasResolvedOpeningPreview", reader)

    def test_remote_chapter_has_one_owner_and_frozen_cursor(self):
        gateway = read_source(SHELF + "BookshelfReaderGatewayView.swift")
        self.assertNotIn("prefetchChapterContent", gateway)
        self.assertIn("initialParagraphIndex: selectedRemoteParagraphIndex", gateway)
        self.assertIn("resumeParagraphIndex(in: chapter.index)", gateway)

    def test_scrolled_shelf_checks_collapsed_navigation_before_expanding_it(self):
        ui = read_source("SourceReadSwiftUITests/FloatingReadingDeskUITests.swift")
        scenario = ui.split("func testReaderReturnPreservesScrolledShelfAndSettingsStack", 1)[1].split("func testReadingDeskReaderAndReturnInTheRealApp", 1)[0]
        frame = scenario.index("XCTAssertEqual(cover.frame.midY, origin.midY")
        collapse = scenario.index("globalSearchButton().isHittable")
        expand = scenario.index("revealNavigation.tap()")
        home = scenario.index("XCTAssertTrue(restoredHome.isHittable")
        settings = scenario.index("XCTAssertTrue(appearanceBar.waitForExistence", home)
        self.assertLess(frame, collapse)
        self.assertLess(collapse, expand)
        self.assertLess(expand, home)
        self.assertLess(home, settings)
        self.assertNotIn('let settings = revealRootTab', scenario)
        self.assertNotIn("scrollEnd.press", scenario)
        root = read_source(APP + "App/RootTabView.swift")
        self.assertIn("onRevealNavigation: { keepsShelfTabsExpanded = true }", root)
        self.assertIn("keepsExpanded ? .never : .onScrollDown", root)
        shelf = read_source(SHELF + "BookshelfView.swift")
        button = shelf.split("private var shelfChromeReveal", 1)[1].split("private func revealShelfChrome", 1)[0]
        self.assertIn("onRevealNavigation?()", button)

    def test_scroll_surface_appearance_does_not_replay_an_old_jump(self):
        reader = read_source(READER)
        surface = reader.split("private var scrollReaderContent", 1)[1].split("// MARK: - Continuous chapter window", 1)[0]
        self.assertNotIn("ParagraphJumpRequest(index: scrollParagraphTarget)", surface)
        self.assertIn("paragraphJumpRequest = ParagraphJumpRequest(index: initial.paragraph)", reader)
        self.assertIn("ParagraphJumpRequest(index: paragraph, utf16Offset: anchor?.paragraphUTF16Offset", reader)

    def test_mounted_reader_ignores_live_progress_writes(self):
        """Live progress must not feed a mounted reader. Every scroll write
        re-renders the gateway; rebuilding `content` from the moving shelf
        cursor reset the window and replayed the launch chapter on a parked
        reader (CI 43318166559: crossed to chapter 3, reopened, landed on 2)."""
        gateway = read_source(SHELF + "BookshelfReaderGatewayView.swift")
        self.assertIn("@State private var surfaceChapterIndex: Int?", gateway)
        self.assertIn("@State private var surfaceParagraphIndex: Int?", gateway)
        self.assertIn("let requestedIndex = surfaceChapterIndex ?? resumeChapterIndex", gateway)
        self.assertIn("let frozenParagraph = surfaceChapterIndex == safeIndex ? surfaceParagraphIndex : nil", gateway)
        # Explicit navigation is the only writer of the surface cursor.
        self.assertIn("moveSurfaceCursor(to:", gateway)
        self.assertIn("if surfaceChapterIndex == nil {", gateway)
        chapter_loader = read_source(DETAIL).split("struct ChapterLoadingView", 1)[1]
        self.assertIn(".task(id: effectiveChapter)", chapter_loader)
        self.assertIn("guard !Task.isCancelled, effectiveChapter == targetChapter", chapter_loader)

    def test_stalled_reader_mount_recovers_instead_of_stranding_prose(self):
        """CI 43318166559 showed `paragraphs=0 building=1` behind a ready shell.
        WebKit drops `evaluateJavaScript` completions when its content process
        dies, so `isBuildingContent` stayed true and every later `update()`
        returned before mounting. The watchdog must clear that state on its own
        timer, because `update()` is exactly what stops being called."""
        web = read_source(READER_WEB)
        self.assertIn("private var contentBuildDeadline: CFTimeInterval = 0", web)
        self.assertIn("private var contentBuildWatchdog: Task<Void, Never>?", web)
        self.assertIn("scheduleContentBuildWatchdog(revision: revision, webView: webView)", web)
        self.assertIn("self.recoverStalledContentBuildIfNeeded(webView: webView, force: true)", web)
        self.assertIn("recoverStalledContentBuildIfNeeded(webView: WKWebView, force: Bool = false)", web)
        # Recovery must clear the latch and force a remount, not merely log.
        recovery = web.split("private func recoverStalledContentBuildIfNeeded", 1)[1]
        self.assertIn("isBuildingContent = false", recovery)
        self.assertIn("lastContentFingerprint = nil", recovery)
        # A terminated content process invalidates any in-flight completion.
        termination = web.split("func webViewWebContentProcessDidTerminate", 1)[1].split("private func activateDocumentIfNeeded", 1)[0]
        self.assertIn("isBuildingContent = false", termination)

    def test_workbench_typography_and_classic_settings_keep_separate_boundaries(self):
        reader = read_source(READER)
        self.assertIn("layoutSettingsBody(showsPreview: false, includesLegacySections: false)", reader)
        self.assertIn("layoutSettingsBody(showsPreview: true)", reader)
        self.assertIn("if includesLegacySections { legacyLayoutHeadingControls }", reader)
        self.assertIn("if includesLegacySections { legacyLayoutStatusControls }", reader)

    def test_cache_cancellation_owns_its_generation_and_resume_uses_actual_cached_urls(self):
        cache = read_source(APP + "Core/Storage/ChapterDownloadStore.swift")
        self.assertIn("tasks[bookID]?.generation == generation", cache)
        self.assertIn("cacheStore.cachedChapterURLs(", cache)
        self.assertIn("cachedChapterIndexes: []", cache)
        self.assertLess(cache.index("try await cacheStore.flush()"),
                        cache.index("for index in completed { store.markCompleted"))
        self.assertGreaterEqual(cache.count("guard self.isCurrentJob(bookID, generation: generation)"), 2)

    def test_source_switch_validates_replacement_before_mutating_current_book(self):
        switch = read_source(SHELF + "BookshelfReaderGatewayView.swift").split("private func applySwitch(", 1)[1].split(
            "private func loadSourceSwitchPreview", 1)[0]
        self.assertIn("await loadSourceSwitchPreview", switch)
        validation = switch.index("await loadSourceSwitchPreview")
        mutation = switch.index("bookshelfStore.switchSource")
        self.assertLess(validation, mutation)
        self.assertIn("requiresNumberedChapterMatch: true", switch)
        self.assertIn("sourceSwitchGeneration == token", switch[validation:mutation])
        self.assertIn("guard let content, !content.paragraphs.isEmpty", switch[validation:mutation])

    def test_diagnostic_clipboard_does_not_include_raw_urls_or_transport_messages(self):
        export = read_source(DETAIL).split("private func chapterDiagnosticText(", 1)[1].split("    init(", 1)[0]
        self.assertTrue(export.startswith(")"))
        self.assertIn("SourceDiagnosticRedactor.originHost(effectiveChapter.url)", export)
        self.assertNotIn("effectiveChapter.bookUrl", export)
        self.assertNotIn("chapterTitle:", export)


if __name__ == "__main__":
    unittest.main()
