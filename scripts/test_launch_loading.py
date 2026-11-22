"""The first window must not wait for source/shelf JSON decoding."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'SourceReadSwift'


class LaunchLoadingTests(unittest.TestCase):
    def test_launch_mounts_before_library_io(self):
        app = (ROOT / 'App/SourceReadSwiftApp.swift').read_text(encoding='utf-8')
        self.assertIn('@StateObject private var launchState = AppLaunchState()', app)
        self.assertNotIn('@StateObject private var appState = ReaderRegressionLaunch.makeAppState()', app)
        self.assertIn('AppLibraryLoadingView()', app)
        self.assertIn('await launchState.load()', app)
        loader = (ROOT / 'App/ReaderRegressionLaunch.swift').read_text(encoding='utf-8')
        self.assertIn('Task.detached(priority: .userInitiated)', loader)
        for label in ['preloadedSources:', 'preloadedBooks:', 'preloadedGroups:']:
            self.assertIn(label, loader)

    def test_loaded_snapshots_do_not_read_disk_again_on_main(self):
        source = (ROOT / 'Core/Storage/SourceStore.swift').read_text(encoding='utf-8')
        self.assertIn('try preloadedSources?.get() ?? persistence.load()', source)
        shelf = (ROOT / 'Core/Storage/BookshelfStore.swift').read_text(encoding='utf-8')
        self.assertIn('try preloadedBooks?.get() ?? persistence.load()', shelf)
        self.assertIn('preloadedGroups?.get() ?? groupPersistence.load()', shelf)

    def test_failed_shelf_load_cannot_seed_over_the_original_file(self):
        shelf = (ROOT / 'Core/Storage/BookshelfStore.swift').read_text(encoding='utf-8')
        seed = shelf.split('func seedOnboardingBookIfNeeded', 1)[1].split('func book(id:', 1)[0]
        self.assertIn('guard books.isEmpty, lastError == nil else { return }', seed)


if __name__ == '__main__':
    unittest.main()
