"""Round-one performance source contracts, not SDK/device performance tests.

Usage: python -B -m unittest discover -s scripts -p test_perf_minimal_scope.py -v
"""
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read_source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class MinimalPerformanceScopeTests(unittest.TestCase):
    def assertContains(self, needle, source):
        self.assertTrue(needle in source, f"Missing source contract: {needle}")

    def assertExcludes(self, needle, source):
        self.assertTrue(needle not in source, f"Forbidden source contract: {needle}")

    def test_reader_does_not_automatically_create_a_display_link(self):
        reader = read_source("SourceReadSwift/Features/Reader/ReaderView.swift")
        self.assertExcludes("ReaderFrameRateSampler.shared.begin()", reader)
        self.assertExcludes("ReaderFrameRateSampler.shared.end()", reader)
        legacy = read_source("SourceReadSwift/Shared/Performance/ReaderFrameRateSampler.swift")
        self.assertExcludes("CADisplayLink(target:", legacy)

    def test_explicit_sampler_does_not_request_a_high_refresh_floor(self):
        profiler = read_source("SourceReadSwift/Shared/Performance/AppFrameProfiler.swift")
        self.assertExcludes("displayLink.preferredFrameRateRange =", profiler)
        self.assertContains("guard !isRecording else { return }", profiler)
        self.assertContains("deadlineTask?.cancel()", profiler)
        self.assertContains("displayLink.invalidate()", profiler)
        self.assertContains("willResignActiveNotification", profiler)
        self.assertContains("ReaderScrollPerfMeter.isRecording = false", profiler)

    def test_diagnostic_labels_do_not_claim_presented_fps(self):
        diagnostics = read_source("SourceReadSwift/Features/Settings/ReaderPerformanceDiagnosticsView.swift")
        for old_label in ['Text("平均帧率")', 'Text("掉帧率")', 'Text("出帧样本")']:
            self.assertExcludes(old_label, diagnostics)
        profiler = read_source("SourceReadSwift/Shared/Performance/AppFrameProfiler.swift")
        self.assertContains("不代表 GPU 实际呈现", profiler)

    def test_normal_scroll_sampling_is_opt_in(self):
        meter = read_source("SourceReadSwift/Shared/Performance/ReaderScrollPerfMeter.swift")
        self.assertContains("guard isRecording else { return }", meter)

    def test_only_explicit_profiler_can_construct_a_display_link(self):
        creators = [str(p.relative_to(ROOT)).replace("\\", "/")
                    for p in (ROOT / "SourceReadSwift").rglob("*.swift")
                    if "CADisplayLink(target:" in p.read_text(encoding="utf-8")]
        self.assertEqual(creators, ["SourceReadSwift/Shared/Performance/AppFrameProfiler.swift"])
        profiler = read_source(creators[0])
        self.assertContains("private init()", profiler)
        self.assertContains("min(max(duration, 0.01), 30)", profiler)

    def test_main_actor_store_bursts_do_not_spawn_one_task_per_mutation(self):
        app = read_source("SourceReadSwift/App/AppState.swift")
        subscriptions = app.split("private func bindChildStores()", 1)[1].split("// MARK:", 1)[0]
        self.assertExcludes("Task {", subscriptions)
        self.assertCountEqual(re.findall(r"(\w+)\.objectWillChange\s*\.sink", subscriptions), [
            "sourceStore", "bookshelfStore", "purifyRuleStore", "chapterDownloadStore",
            "rssArticleStateStore", "rssFeedCacheStore", "rssArticleContentCacheStore",
            "sourceHealthStore", "sourceDiagnosticHistoryStore", "readingHistoryStore",
        ])
        self.assertEqual(subscriptions.count("scheduleStoreNotification()"), 10)

    def test_progress_and_session_writes_are_ordered_off_main(self):
        persistence = read_source("SourceReadSwift/Core/Storage/BookshelfPersistence.swift")
        self.assertContains("Self.diskQueue.async", persistence)
        self.assertContains("Self.diskQueue.sync", persistence)
        self.assertContains("func saveReadingProgressInBackground", persistence)
        self.assertContains("func waitForPendingWrites() async", persistence)
        store = read_source("SourceReadSwift/Core/Storage/BookshelfStore.swift")
        progress = store.split("private func persistReadingProgress()", 1)[1].split("private func persistNow", 1)[0]
        self.assertContains("saveReadingProgressInBackground", progress)
        self.assertExcludes("try persistence.saveReadingProgress(books)", progress)
        session = store.split("func recordReadingSession(", 1)[1].split("func remove(", 1)[0]
        self.assertContains("persistInBackground()", session)

    def test_read_history_is_part_of_the_same_off_main_investigation(self):
        history = read_source("SourceReadSwift/Core/Storage/ReadingHistoryStore.swift")
        self.assertContains("func saveInBackground", history)
        self.assertContains("persist(inBackground: true)", history)
        self.assertContains("Self.diskQueue.sync", history)
        self.assertContains("history = nextHistory", history)

    def test_global_notifications_keep_remaining_shared_subscriptions(self):
        app = read_source("SourceReadSwift/App/AppState.swift")
        self.assertContains("guard !hasPendingStoreNotification else { return }", app)
        for store in ["bookshelfStore", "readingHistoryStore", "chapterDownloadStore"]:
            self.assertContains(f"{store}.objectWillChange", app)
        self.assertContains("scheduleStoreNotification()", app)

    def test_chapter_prefetch_invalidates_only_the_cache_consumers(self):
        app = read_source("SourceReadSwift/App/AppState.swift")
        self.assertExcludes("chapterContentCacheStore.objectWillChange", app)
        settings = read_source("SourceReadSwift/Features/Settings/SettingsView.swift")
        self.assertContains("OfflineChapterCacheView(store: appState.chapterContentCacheStore)", settings)
        cache_views = read_source("SourceReadSwift/Features/Settings/ReaderDataManagementViews.swift")
        body = cache_views.split("struct OfflineChapterCacheView: View", 1)[1].split("var body:", 1)[0]
        self.assertContains("@ObservedObject var store: ChapterContentCacheStore", body)

    def test_curl_controller_reservation_does_not_eagerly_load_distant_page_trees(self):
        curl = read_source("SourceReadSwift/Features/Reader/PageCurlReaderView.swift")
        reserve = curl.split("func viewController(at index:", 1)[1].split("func noteContentRevision", 1)[0]
        self.assertExcludes("controller.view.", reserve)
        setup = curl.split("override func viewDidLoad()", 1)[1].split("override func viewDidLayoutSubviews", 1)[0]
        self.assertContains("view.backgroundColor = pageBackgroundColor ?? .clear", setup)
        self.assertContains("view.isOpaque = pageBackgroundColor != nil", setup)

    def test_background_boundary_captures_position_before_draining_writes(self):
        reader = read_source("SourceReadSwift/Features/Reader/ReaderView.swift")
        boundary = reader.split(".onChange(of: scenePhase)", 1)[1].split(".onChange(of: bindingRevision)", 1)[0]
        self.assertContains("guard !readerSessionEnded else { return }", boundary)
        self.assertContains("finishReadingWritesInBackground {", boundary)
        self.assertContains("persistReadingPosition(", boundary)
        app = read_source("SourceReadSwift/App/AppState.swift")
        flush = app.split("func finishReadingWritesInBackground(", 1)[1].split("private func scheduleStoreNotification", 1)[0]
        self.assertLess(flush.index("ReadingWriteBackgroundLease()"), flush.index("capturingPosition()"))
        self.assertLess(flush.index("capturingPosition()"), flush.index("await bookshelfStore.waitForPendingWrites()"))
        self.assertContains("await bookshelfStore.waitForPendingWrites()", app)
        self.assertContains("await readingHistoryStore.waitForPendingWrites()", app)


if __name__ == "__main__":
    unittest.main()
