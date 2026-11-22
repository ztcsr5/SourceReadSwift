"""Guard the November 22 follow-up without changing the resolved high-refresh path."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(relative):
    return (ROOT / relative).read_text(encoding='utf-8')


class ForestFollowupTests(unittest.TestCase):
    def test_fresh_defaults_keep_showcase_but_restore_forest(self):
        theme = read('SourceReadSwift/Shared/DesignSystem/AppVisualTheme.swift')
        self.assertIn('static let initialSelection: Self = .forest', theme)
        self.assertIn('isExistingInstall ? Self.classic : Self.showcase',
                      read('SourceReadSwift/Features/Bookshelf/HomeBookPresentation.swift'))

    def test_forest_wash_is_global_but_only_showcase_uses_the_cover(self):
        page = read('SourceReadSwift/Shared/DesignSystem/AppTheme.swift')
        self.assertIn('theme == .forest', page)
        self.assertIn('ForestGlassBackdrop()', page)
        wash = read('SourceReadSwift/Shared/DesignSystem/ForestGlassBackdrop.swift')
        self.assertNotIn('.blur(', wash)
        self.assertNotIn('Timer', wash)
        home = read('SourceReadSwift/Features/Bookshelf/HomeShowcaseBackdrop.swift')
        self.assertNotIn('geometry.size.width * 1.9', home)
        self.assertNotIn('.mask', home)
        self.assertIn('imageURL == coverURL', home)

    def test_button_owns_its_contrasting_ink_and_cards_let_the_wash_through(self):
        display = read('SourceReadSwift/Features/Bookshelf/HomeBookDisplay.swift')
        button = display.split('Label("继续阅读"', 1)[1].split('if resolvedMediaKind', 1)[0]
        self.assertIn('.foregroundStyle(AppTheme.prominentInk)', button)
        self.assertIn('.tint(AppTheme.prominentFill)', button)
        surfaces = read('SourceReadSwift/Shared/DesignSystem/AppThemeSurface.swift')
        self.assertIn('current.usesTintedPaper', surfaces)
        self.assertIn('theme.usesTintedPaper', surfaces)
        self.assertNotIn('.background(AppThemeRowSurface(), in:', display)

    def test_shelf_entries_open_reader_and_keep_explicit_details(self):
        shelf = read('SourceReadSwift/Features/Bookshelf/BookshelfView.swift')
        for name in ['bookshelfRow', 'bookshelfGridCard', 'updateRow']:
            section = shelf.split('private func ' + name, 1)[1].split('.buttonStyle', 1)[0]
            self.assertIn('openShelfBook(book, placement:', section)
            self.assertNotIn('NavigationLink', section)
        self.assertIn('sourceID: placement + "|" + book.id', shelf)
        collection = shelf.split('private struct BookshelfCollectionView', 1)[1]
        self.assertIn('readerNavigation.open(.shelf(book, sourceID: "collection|" + book.id))', collection)
        self.assertIn('Label("书籍详情", systemImage: "info.circle")', collection)

    def test_settings_about_and_source_management_scope(self):
        settings = read('SourceReadSwift/Features/Settings/SettingsView.swift')
        self.assertLess(settings.index('Section("AI 与写源")'), settings.index('Section("书库与记录")'))
        about = read('SourceReadSwift/Features/Settings/AboutReadView.swift')
        for deleted in ['SettingsQQGroupRow', 'Section("致谢与声明")']:
            self.assertNotIn(deleted, about)
        self.assertIn('about.readingGuide', about)
        self.assertIn('PrivacyLegalHubView()', about)
        source = read('SourceReadSwift/Features/SourceManager/SourceManagerView.swift')
        self.assertNotIn('private var sourceManagerHeader:', source)
        self.assertIn('sourceManagerToolbar', source)
        self.assertNotIn('source.enabled ? .green : .gray', source)

    def test_refresh_driver_and_packaged_capability_are_untouched(self):
        for path in ['SourceReadSwift/App/AppRefreshRateKeeper.swift',
                     'SourceReadSwift/Shared/Performance/FrameRateCoordinator.swift',
                     'SourceReadSwift/App/Info.plist']:
            old = subprocess.check_output(['git', 'show', '34d19484:' + path], cwd=ROOT)
            self.assertEqual((ROOT / path).read_bytes().replace(b'\r\n', b'\n'), old.replace(b'\r\n', b'\n'))

    def test_background_and_foreground_work_does_not_create_unused_io_on_transition(self):
        app = read('SourceReadSwift/App/AppState.swift')
        flush = app.split('func finishReadingWritesInBackground', 1)[1].split('private func scheduleStoreNotification', 1)[0]
        self.assertIn('let readingHistoryStore = loadedReadingHistoryStore', flush)
        launch = read('SourceReadSwift/App/SourceReadSwiftApp.swift')
        self.assertIn('if phase == .background, !isRunningUnitTests', launch)
        self.assertIn('.task(id: scenePhase, priority: .utility)', launch)
        sync = read('SourceReadSwift/Core/Network/WebDAVAutoSyncCoordinator.swift').split('func checkForNewerRemoteBackupIfNeeded()', 1)[1]
        self.assertLess(sync.index('guard let username'), sync.index('currentConfig(defaults: defaults)'))

    def test_import_screen_is_byte_for_byte_unchanged(self):
        path = 'SourceReadSwift/Features/SourceManager/SourceManagerView.swift'
        previous = subprocess.check_output(['git', 'show', '34d19484:' + path], cwd=ROOT).decode('utf-8')
        source = read(path)
        start = '    private var importSheet: some View {'
        end = '    private var importSourceActionGroup:'
        self.assertEqual(source.split(start, 1)[1].split(end, 1)[0], previous.split(start, 1)[1].split(end, 1)[0])

    def test_detail_can_return_without_a_native_modal_zoom_settle_tail(self):
        detail = read('SourceReadSwift/Features/Discover/BookDetailView.swift')
        self.assertIn('returnsToDetail: true', detail)
        router = read('SourceReadSwift/Features/Reader/Navigation/ReaderNavigationRouter.swift')
        self.assertIn('if returnsToDetail, navigationStyle.usesNativeZoom { navigationStyle = .system }', router)

    def test_sheet_resize_does_not_auto_scroll_or_sort_the_same_library_twice(self):
        directory = read('SourceReadSwift/Features/Reader/ReaderChapterDirectoryList.swift')
        self.assertNotIn('placedMetrics != metrics', directory)
        self.assertIn('placedRowHeight != rowHeight', directory)
        source = read('SourceReadSwift/Features/SourceManager/SourceManagerView.swift')
        content = source.split('private var bookSourceContent:', 1)[1].split('private var catalogContent:', 1)[0]
        self.assertEqual(content.count('filteredBookSources'), 1)


if __name__ == '__main__':
    unittest.main()
