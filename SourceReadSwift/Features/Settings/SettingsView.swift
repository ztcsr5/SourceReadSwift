import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @ObservedObject private var proxyManager = SourceProxyManager.shared
    @AppStorage("app.hapticsEnabled") private var hapticsEnabled = false
    @AppStorage("search_concurrent_threads") private var searchThreads = 12
    @AppStorage("batch_check_concurrent_threads") private var batchCheckThreads = 4
    @AppStorage("settings.accentHex") private var accentHex = "594FDB"
    @AppStorage("settings.secondaryAccentHex") private var secondaryAccentHex = "419BDC"
    @State private var cacheSize = "无缓存"
    @State private var rssCacheSize = "无缓存"
    @State private var backupDocument: AppDataBackupDocument?
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var backupMessage: String?
    /// 清零采样后强制刷新诊断区。
    @State private var perfRefreshToken = UUID()

    private var themeMode: ThemeMode {
        get { ThemeMode(rawValue: themeModeRawValue) ?? .system }
        set { themeModeRawValue = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                settingsHeroSection

                Section("外观") {
                    ForEach(ThemeMode.allCases) { mode in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.22)) {
                                themeModeRawValue = mode.rawValue
                            }
                        } label: {
                            HStack {
                                Text(mode.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if themeMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                    }
                }

                Section("自定义外观") {
                    ColorPicker("主题主色", selection: Binding(get: { AppTheme.accent }, set: { if let hex = AppTheme.hex($0) { accentHex = hex } }), supportsOpacity: false)
                    ColorPicker("主题辅色", selection: Binding(get: { AppTheme.secondaryAccent }, set: { if let hex = AppTheme.hex($0) { secondaryAccentHex = hex } }), supportsOpacity: false)
                    HStack(spacing: 8) {
                        ForEach(["594FDB", "267A62", "B75473", "B76A2C", "3476B8"], id: \.self) { hex in
                            Button { accentHex = hex } label: {
                                Circle().fill(Color(uiColor: colorFromHex(hex))).frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(.primary.opacity(accentHex == hex ? 0.8 : 0), lineWidth: 2))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.plain).accessibilityLabel("主题色 \(hex)")
                        }
                    }
                    Button("恢复纸间默认配色") { accentHex = "594FDB"; secondaryAccentHex = "419BDC" }
                    Text("只调整应用界面配色，不覆盖书籍的阅读背景和字体颜色。").font(.caption).foregroundStyle(.secondary)
                }

                Section("排版与字体") {
                    NavigationLink {
                        CustomFontManagementView().hideRootTabBar()
                    } label: {
                        Label("字体管理与自定义导入", systemImage: "textformat")
                    }
                }

                Section("语音朗读") {
                    NavigationLink {
                        TTSSettingsView().hideRootTabBar()
                    } label: {
                        Label("朗读引擎与云端凭据", systemImage: "waveform")
                    }
                }

                Section("内容设置") {
                    NavigationLink {
                        SourceManagerView()
                            .environmentObject(appState)
                            .hideRootTabBar()
                    } label: {
                        Label("书源管理", systemImage: "books.vertical")
                    }

                    NavigationLink {
                        SourceLoginCenterView(
                            sources: appState.sourceStore.sources,
                            cookieStore: appState.sourceCookieStore,
                            engine: appState.engine
                        )
                    } label: {
                        Label("书源登录中心", systemImage: "key.fill")
                    }

                    NavigationLink {
                        CookieManagerView(cookieStore: appState.sourceCookieStore).hideRootTabBar()
                    } label: {
                        Label("会话与 Cookie 管理", systemImage: "network.badge.shield.half.filled")
                    }

                    NavigationLink {
                        SourceWritingView(server: appState.sourceWritingServer)
                            .environmentObject(appState)
                            .hideRootTabBar()
                    } label: {
                        Label("Web 写源与传输服务", systemImage: "globe")
                    }

                    NavigationLink {
                        RuleHealthView().hideRootTabBar()
                    } label: {
                        Label("规则体检", systemImage: "shield")
                    }

                    NavigationLink {
                        PurifyRulesView().hideRootTabBar()
                    } label: {
                        Label("净化规则", systemImage: "wand.and.stars")
                    }

                    NavigationLink {
                        SourceProxySettingsView().hideRootTabBar()
                    } label: {
                        HStack {
                            Label("书源网络代理", systemImage: "network")
                            Spacer()
                            Text(proxyManager.isEnabled ? "\(proxyManager.host):\(proxyManager.port)" : "未开启")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("交互与反馈") {
                    Toggle("触控震动反馈", isOn: $hapticsEnabled)
                        .onChange(of: hapticsEnabled) { enabled in
                            UserDefaults.standard.set(enabled, forKey: "app.hapticsEnabled")
                        }
                }

                Section("并发与性能") {
                    Stepper("搜书并发线程数: \(searchThreads) 线程", value: $searchThreads, in: 2...32)
                    Stepper("书源校验并发线程数: \(batchCheckThreads) 线程", value: $batchCheckThreads, in: 1...16)
                }

                Section("通用") {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        appState.chapterContentCacheStore.removeAll()
                        updateCacheSummary()
                    } label: {
                        HStack {
                            Label("清理章节缓存", systemImage: "trash")
                            Spacer()
                            Text(cacheSize)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        appState.rssFeedCacheStore.removeAll()
                        appState.rssArticleContentCacheStore.removeAll()
                        rssCacheSize = "无缓存"
                    } label: {
                        HStack {
                            Label("清理 RSS 缓存", systemImage: "newspaper.trash")
                            Spacer()
                            Text(rssCacheSize)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        ReadingHistoryView()
                    } label: {
                        Label("阅读历史", systemImage: "clock")
                    }

                    NavigationLink {
                        ReadingStatsView()
                    } label: {
                        Label("阅读统计", systemImage: "chart.bar.xaxis")
                    }

                    NavigationLink {
                        ReaderBookmarksView()
                    } label: {
                        Label("全部书签", systemImage: "bookmark")
                    }

                    NavigationLink {
                        OfflineChapterCacheView()
                    } label: {
                        Label("离线章节", systemImage: "arrow.down.circle")
                    }
                    NavigationLink {
                        AboutReadView()
                    } label: {
                        Label("关于纸间", systemImage: "info.circle")
                    }
                }

                Section("数据") {
                    NavigationLink {
                        WebDAVSyncView()
                            .environmentObject(appState)
                    } label: {
                        Label("WebDAV 云端同步与备份", systemImage: "icloud.and.arrow.up")
                    }

                    Button {
                        backupDocument = AppDataBackupDocument(snapshot: appState.makeAppDataBackupSnapshot())
                        showBackupExporter = true
                    } label: {
                        Label("导出完整数据", systemImage: "externaldrive.badge.icloud")
                    }

                    Button {
                        showBackupImporter = true
                    } label: {
                        Label("恢复完整数据", systemImage: "arrow.clockwise.icloud")
                    }
                }

                Section {
                    let perf = ReaderScrollPerfMeter.snapshot
                    HStack {
                        Text("滚动回调平均耗时")
                        Spacer()
                        Text(String(format: "%.2f ms", perf.averageMilliseconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("最差一次")
                        Spacer()
                        Text(String(format: "%.2f ms", perf.worstMilliseconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("样本帧数")
                        Spacer()
                        Text("\(perf.frames)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    let frameRate = ReaderFrameRateSampler.snapshot
                    HStack {
                        Text("平均帧率")
                        Spacer()
                        Text(String(format: "%.1f fps", frameRate.averageFPS))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("掉帧率")
                        Spacer()
                        Text(String(format: "%.1f%%（%d 帧）", frameRate.droppedRatio * 100, frameRate.droppedFrames))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("出帧样本")
                        Spacer()
                        Text("\(frameRate.frames)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Button("清零重新采样") {
                        ReaderScrollPerfMeter.reset()
                        ReaderFrameRateSampler.reset()
                        perfRefreshToken = UUID()
                    }
                } header: {
                    Text("阅读器性能（诊断）")
                } footer: {
                    Text("滚动回调耗时小于 2ms 说明瓶颈在界面重建，大于 6ms 说明在文字排版；掉帧率超过 5% 就是肉眼可见的卡。滚动几章后回来看数字。")
                }
                .id(perfRefreshToken)

                Section("诊断") {
                    NavigationLink {
                        RecentDiagnosticsView(events: appState.diagnostics).hideRootTabBar()
                    } label: {
                        Label("最近诊断 · 查看与复制", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .pageBackground()
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .animation(.easeInOut(duration: 0.22), value: themeModeRawValue)
            .onAppear {
                updateCacheSummary()
                appState.chapterContentCacheStore.removeExpired()
                updateCacheSummary()
                updateRSSCacheSummary()
            }
            .fileExporter(
                isPresented: $showBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "SourceReadSwift-bookshelf-backup"
            ) { result in
                switch result {
                case .success:
                    backupMessage = "完整数据已导出"
                case .failure(let error):
                    backupMessage = "导出失败：\(error.localizedDescription)"
                }
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                importBackup(result)
            }
            .alert("数据备份", isPresented: Binding(
                get: { backupMessage != nil },
                set: { if !$0 { backupMessage = nil } }
            )) {
                Button("确定") { backupMessage = nil }
            } message: {
                Text(backupMessage ?? "")
            }
        }
    }

    private func colorFromHex(_ hex: String) -> UIColor {
        let n = UInt32(hex, radix: 16) ?? 0x594FDB
        return UIColor(red: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }

    private var settingsHeroSection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [AppTheme.accent, AppTheme.secondaryAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text("纸间").font(.system(size: 25, weight: .semibold, design: .serif))
                    Text("把时间留给阅读").font(.subheadline).foregroundStyle(.secondary)
                    Text(AppVersion.fullDisplayString).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func settingsHeroMetric(_ title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.6)
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw AppDataBackupError.fileReadFailed(error.localizedDescription)
            }
            let snapshot = try AppDataBackupCodec.decode(
                data: data,
                fallbackSources: appState.sourceStore.backupSnapshot(),
                fallbackPurifyRules: appState.purifyRuleStore.backupSnapshot(),
                fallbackRSSState: appState.rssArticleStateStore.backupSnapshot()
            )
            // Capture the complete current state before the first mutation so
            // any later store failure can restore all stores and preferences.
            let previousSnapshot = appDataBackupSnapshot()
            try AppDataBackupRestorer.restore(
                snapshot,
                previous: previousSnapshot,
                restoreBookshelf: { appState.bookshelfStore.restore($0) },
                restoreSources: { appState.sourceStore.restore($0) },
                restorePurifyRules: { appState.purifyRuleStore.restore($0) },
                restoreRSSState: { appState.rssArticleStateStore.restore($0) },
                restorePreferences: { restoreReaderPreferences($0) }
            )
            updateCacheSummary()
            updateRSSCacheSummary()
            backupMessage = "已恢复 \(snapshot.bookshelf.books.count) 本书、\(snapshot.sources.sources.count) 个书源和 \(snapshot.purifyRules.count) 条规则"
        } catch {
            backupMessage = "恢复失败：\(error.localizedDescription)"
        }
    }

    private func updateCacheSummary() {
        let chapters = appState.chapterContentCacheStore.entries.count
        cacheSize = chapters == 0
            ? "无缓存"
            : "\(chapters) 章 / \(byteCountText(appState.chapterContentCacheStore.estimatedByteCount))"
    }

    private func appDataBackupSnapshot() -> AppDataBackupSnapshot {
        let keys = [
            "reader.fontSize", "reader.lineSpacing", "reader.pagePadding", "reader.letterSpacing",
            "reader.paragraphSpacing", "reader.paragraphIndent", "reader.titleSpacing", "reader.footerHeight",
            "reader.ttsRate", "reader.autoScrollDelay", "reader.sleepTimerMinutes", "reader.background",
            "reader.mode", "reader.tapZones", "reader.keepScreenAwake", "reader.preloadChapterCount",
            "reader.textSelectionEnabled", "settings.themeMode"
        ]
        let defaults = UserDefaults.standard
        let doubleKeys: Set<String> = [
            "reader.fontSize", "reader.lineSpacing", "reader.pagePadding", "reader.letterSpacing",
            "reader.paragraphSpacing", "reader.paragraphIndent", "reader.titleSpacing", "reader.footerHeight",
            "reader.ttsRate", "reader.autoScrollDelay"
        ]
        let integerKeys: Set<String> = ["reader.sleepTimerMinutes", "reader.preloadChapterCount"]
        let boolKeys: Set<String> = ["reader.keepScreenAwake", "reader.textSelectionEnabled"]
        let preferences = Dictionary(uniqueKeysWithValues: keys.compactMap { key -> (String, BackupPreferenceValue)? in
            guard let value = defaults.object(forKey: key) else { return nil }
            if doubleKeys.contains(key) {
                return (key, .double((value as? NSNumber)?.doubleValue ?? (value as? Double) ?? 0))
            }
            if integerKeys.contains(key) {
                return (key, .integer((value as? NSNumber)?.intValue ?? (value as? Int) ?? 0))
            }
            if boolKeys.contains(key) {
                return (key, .bool((value as? NSNumber)?.boolValue ?? (value as? Bool) ?? false))
            }
            if let string = value as? String { return (key, .string(string)) }
            return nil
        })
        return AppDataBackupSnapshot(
            bookshelf: appState.bookshelfStore.backupSnapshot(),
            sources: appState.sourceStore.backupSnapshot(),
            purifyRules: appState.purifyRuleStore.backupSnapshot(),
            rssState: appState.rssArticleStateStore.backupSnapshot(),
            readerPreferences: preferences
        )
    }

    private func restoreReaderPreferences(_ preferences: [String: BackupPreferenceValue]) {
        let defaults = UserDefaults.standard
        for (key, value) in preferences {
            switch value {
            case .string(let value): defaults.set(value, forKey: key)
            case .double(let value): defaults.set(value, forKey: key)
            case .integer(let value): defaults.set(value, forKey: key)
            case .bool(let value): defaults.set(value, forKey: key)
            }
        }
    }

    private func updateRSSCacheSummary() {
        let count = appState.rssFeedCacheStore.entries.reduce(0) { $0 + $1.articles.count }
        let bodies = appState.rssArticleContentCacheStore.entries.count
        rssCacheSize = count == 0 && bodies == 0
            ? "无缓存"
            : "\(count) 篇 / \(appState.rssFeedCacheStore.entries.count) 源 / 正文 \(bodies)"
    }

    private func byteCountText(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    private func diagnosticExportText(events: [DiagnosticEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        return events.prefix(200).map { event in
            var lines = [
                "[\(event.level.rawValue.uppercased())] \(formatter.string(from: event.date))",
                "stage: \(event.stage)",
                "message: \(event.message)"
            ]
            if let sourceName = event.sourceName {
                lines.append("source: \(sourceName)")
            }
            for item in event.details.sorted(by: { $0.key < $1.key }) {
                lines.append("\(item.key): \(item.value)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n---\n\n")
    }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case eyeCare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色模式"
        case .dark: return "深色模式"
        case .eyeCare: return "护眼模式"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .eyeCare: return .light
        case .dark: return .dark
        }
    }
}

struct ReadingHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmClearAll = false

    private var history: [ReadingHistoryItem] {
        appState.readingHistoryStore.history
    }

    var body: some View {
        List {
            if history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("暂无阅读历史")
                        .font(.headline)
                    Text("看书后会自动在此记录阅读进度，即使将书移出书架，历史记录也会独立保留。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
            } else {
                ForEach(history) { item in
                    NavigationLink {
                        BookshelfReaderGatewayView(book: item.asBookshelfBook)
                    } label: {
                        HStack(spacing: 12) {
                            AsyncBookCover(urlString: item.coverURL, width: 44, height: 60)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(item.readingProgress * 100))%")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                                Text(item.currentChapterTitle ?? "尚未开始")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                HStack(spacing: 10) {
                                    Label("\(item.readingSessionCount) 次", systemImage: "book")
                                    Label(readingDurationText(item.totalReadingSeconds), systemImage: "timer")
                                    Spacer()
                                    Text(item.lastReadAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("删除记录", role: .destructive) {
                            appState.readingHistoryStore.remove(id: item.id)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if !appState.bookshelfStore.contains(item.asSearchBook) {
                            Button {
                                appState.bookshelfStore.addOrUpdate(item.asSearchBook)
                            } label: {
                                Label("加回书架", systemImage: "plus.circle")
                            }
                            .tint(AppTheme.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle("阅读历史")
        .toolbar {
            if !history.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        confirmClearAll = true
                    }
                }
            }
        }
        .confirmationDialog("确定清空全部阅读历史？", isPresented: $confirmClearAll, titleVisibility: .visible) {
            Button("清空全部历史", role: .destructive) {
                appState.readingHistoryStore.removeAll()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func readingDurationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "少于 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        return String(format: "%.1f 小时", Double(minutes) / 60.0)
    }
}

struct ReadingStatsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("reading.dailyGoalMinutes") private var dailyGoalMinutes: Int = 30

    private var summary: ReadingStatsSummary {
        ReadingStatsSummary(books: appState.bookshelfStore.books)
    }

    private var todayMinutes: Int {
        Int(summary.todayReadingSeconds / 60)
    }

    private var goalProgress: Double {
        guard dailyGoalMinutes > 0 else { return 0 }
        return min(max(Double(todayMinutes) / Double(dailyGoalMinutes), 0), 1.0)
    }

    var body: some View {
        List {
            if summary.totalBooks == 0 {
                emptyState
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 7)
                                    .frame(width: 58, height: 58)
                                Circle()
                                    .trim(from: 0, to: goalProgress)
                                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                    .frame(width: 58, height: 58)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeInOut(duration: 0.4), value: goalProgress)
                                Text("\(Int(goalProgress * 100))%")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("今日阅读 \(todayMinutes) 分钟")
                                    .font(.headline)
                                Text(goalProgress >= 1.0 ? "🎉 今日目标已达成！保持专注！" : "目标 \(dailyGoalMinutes) 分钟 · 还差 \(max(0, dailyGoalMinutes - todayMinutes)) 分钟")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)

                        HStack(spacing: 6) {
                            Text("目标")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            ForEach([15, 30, 45, 60, 90], id: \.self) { mins in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    dailyGoalMinutes = mins
                                } label: {
                                    Text("\(mins)分")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(dailyGoalMinutes == mins ? AppTheme.accent : Color.secondary.opacity(0.12), in: Capsule())
                                        .foregroundStyle(dailyGoalMinutes == mins ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 10) {
                            statCard("今日阅读", value: "\(todayMinutes) 分钟", icon: "flame.fill", tint: .orange)
                            statCard("连续阅读", value: "\(summary.streakDays) 天", icon: "calendar.badge.clock", tint: .red)
                        }
                        HStack(spacing: 10) {
                            statCard("累计时长", value: durationText(summary.totalReadingSeconds), icon: "timer", tint: AppTheme.accent)
                            statCard("估算字数", value: formatWordCount(summary.estimatedWordsRead), icon: "character.book.closed", tint: .purple)
                        }
                        HStack(spacing: 10) {
                            statCard("阅读次数", value: "\(summary.totalSessions) 次", icon: "book", tint: .green)
                            statCard("平均进度", value: "\(Int(summary.averageProgress * 100))%", icon: "chart.line.uptrend.xyaxis", tint: .blue)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("阅读概览")
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("近 7 天阅读时长")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        let maxSeconds = max(summary.weeklyDistribution.map(\.seconds).max() ?? 1, 60)
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(summary.weeklyDistribution) { item in
                                VStack(spacing: 6) {
                                    let mins = Int(item.seconds / 60)
                                    Text(mins > 0 ? "\(mins)" : "")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(item.isToday ? AppTheme.accent : .secondary)
                                        .frame(height: 12)

                                    let barHeight = max(6, CGFloat(item.seconds / maxSeconds) * 72)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(item.isToday ? AppTheme.accent : Color.secondary.opacity(0.25))
                                        .frame(height: barHeight)

                                    Text(item.dayLabel)
                                        .font(.caption2)
                                        .fontWeight(item.isToday ? .bold : .regular)
                                        .foregroundStyle(item.isToday ? AppTheme.accent : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 110, alignment: .bottom)
                        .padding(.top, 4)

                        let weeklyTotal = summary.weeklyDistribution.reduce(0) { $0 + $1.seconds }
                        let activeDays = summary.weeklyDistribution.filter { $0.seconds > 60 }.count
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("本周累计")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(durationText(weeklyTotal))
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("日均时长")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(durationText(weeklyTotal / 7.0))
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("活跃天数")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(activeDays)/7 天")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("阅读趋势")
                }

                Section("多维媒介生态") {
                    let total = max(1, summary.totalBooks)
                    let audioCount = appState.bookshelfStore.books.filter { mediaKind(for: $0) == .audio }.count
                    let comicCount = appState.bookshelfStore.books.filter { mediaKind(for: $0) == .comic }.count
                    let videoCount = appState.bookshelfStore.books.filter { mediaKind(for: $0) == .video }.count
                    let novelCount = max(0, summary.totalBooks - audioCount - comicCount - videoCount)

                    VStack(alignment: .leading, spacing: 10) {
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.blue)
                                    .frame(width: max(4, geo.size.width * CGFloat(novelCount) / CGFloat(total)))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.green)
                                    .frame(width: max(4, geo.size.width * CGFloat(audioCount) / CGFloat(total)))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.purple)
                                    .frame(width: max(4, geo.size.width * CGFloat(comicCount) / CGFloat(total)))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.red)
                                    .frame(width: max(4, geo.size.width * CGFloat(videoCount) / CGFloat(total)))
                            }
                        }
                        .frame(height: 8)
                        .padding(.vertical, 2)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            formatPill(title: "小说文本", count: novelCount, percent: Int(Double(novelCount)/Double(total)*100), color: .blue, icon: "book.fill")
                            formatPill(title: "有声听书", count: audioCount, percent: Int(Double(audioCount)/Double(total)*100), color: .green, icon: "headphones")
                            formatPill(title: "漫画画册", count: comicCount, percent: Int(Double(comicCount)/Double(total)*100), color: .purple, icon: "character.book.closed.fill")
                            formatPill(title: "影视视频", count: videoCount, percent: Int(Double(videoCount)/Double(total)*100), color: .red, icon: "play.tv.fill")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("阅读成就勋章") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(badges) { badge in
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(badge.isUnlocked ? badge.tint.opacity(0.18) : Color.secondary.opacity(0.1))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: badge.icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(badge.isUnlocked ? badge.tint : .secondary.opacity(0.4))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(badge.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(badge.isUnlocked ? .primary : .secondary)
                                    Text(badge.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("书架构成") {
                    metricRow("书架书籍", value: "\(summary.totalBooks) 本")
                    metricRow("在线书籍", value: "\(summary.remoteBooks) 本")
                    metricRow("本地导入", value: "\(summary.localBooks) 本")
                    metricRow("已阅读", value: "\(summary.readBooks) 本")
                    metricRow("有书签", value: "\(summary.bookmarkedBooks) 本 (共 \(summary.totalBookmarks) 处)")
                }

                if let mostReadBook = summary.mostReadBook {
                    Section("阅读最多") {
                        NavigationLink {
                            BookshelfReaderGatewayView(book: mostReadBook)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(mostReadBook.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("\(durationText(mostReadBook.totalReadingSeconds ?? 0)) · 共阅读 \(mostReadBook.readingSessionCount ?? 0) 次")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("最近阅读") {
                    ForEach(summary.recentBooks) { book in
                        NavigationLink {
                            BookshelfReaderGatewayView(book: book)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(book.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(book.readingProgress * 100))%")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }
                                if let lastReadAt = book.lastReadAt {
                                    Text(lastReadAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("阅读统计")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text("暂无统计")
                .font(.headline)
            Text("打开书籍阅读后，这里会汇总阅读时长、次数、趋势图表与书签。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private func statCard(_ title: String, value: String, icon: String, tint: Color = AppTheme.accent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "少于 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = Double(minutes) / 60.0
        return String(format: "%.1f 小时", hours)
    }

    private func formatWordCount(_ words: Int) -> String {
        if words < 1000 {
            return "\(words) 字"
        } else if words < 10000 {
            return String(format: "%.1f 千字", Double(words) / 1000.0)
        } else {
            return String(format: "%.1f 万字", Double(words) / 10000.0)
        }
    }

    private struct ReadingBadge: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let isUnlocked: Bool
        let tint: Color
    }

    private var badges: [ReadingBadge] {
        let has1Hour = summary.totalReadingSeconds >= 3600
        let has5Books = summary.totalBooks >= 5
        let has3DayStreak = summary.streakDays >= 3
        let audioCount = appState.bookshelfStore.books.filter { mediaKind(for: $0) == .audio }.count
        let comicCount = appState.bookshelfStore.books.filter { mediaKind(for: $0) == .comic }.count
        let videoCount = appState.bookshelfStore.books.filter { mediaKind(for: $0) == .video }.count
        let textCount = max(0, summary.totalBooks - audioCount - comicCount - videoCount)
        let activeKinds = [textCount > 0, audioCount > 0, comicCount > 0, videoCount > 0].filter { $0 }.count
        let isMultiFormat = activeKinds >= 2

        return [
            ReadingBadge(id: "1h", title: "初入书海", subtitle: "阅读超 1 小时", icon: "sparkles", isUnlocked: has1Hour, tint: .orange),
            ReadingBadge(id: "streak", title: "持之以恒", subtitle: "连续阅读 3 天", icon: "flame.fill", isUnlocked: has3DayStreak, tint: .red),
            ReadingBadge(id: "5books", title: "博览群书", subtitle: "藏书超 5 部", icon: "books.vertical.fill", isUnlocked: has5Books, tint: .blue),
            ReadingBadge(id: "multi", title: "多维读者", subtitle: "多媒介探索", icon: "cube.transparent.fill", isUnlocked: isMultiFormat, tint: .purple)
        ]
    }

    private func mediaKind(for book: BookshelfBook) -> BookSourceKind? {
        appState.sourceStore.source(for: book.sourceURL)?.sourceKind
    }

    private func formatPill(title: String, count: Int, percent: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(count) 部 · \(percent)%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RuleHealthView: View {
    @EnvironmentObject private var appState: AppState

    private var sourceStats: RuleHealthStats {
        RuleHealthStats(sources: appState.sourceStore.sources)
    }

    var body: some View {
        List {
            Section("总览") {
                metricRow("书源总数", value: "\(sourceStats.total)")
                metricRow("启用书源", value: "\(sourceStats.enabled)")
                metricRow("可搜索", value: "\(sourceStats.searchable)")
                metricRow("可读正文", value: "\(sourceStats.readable)")
            }

            Section("需要处理") {
                if sourceStats.problemSources.isEmpty {
                    Label("当前未发现明显规则缺失", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(sourceStats.problemSources) { source in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(source.bookSourceName)
                                .font(.headline)
                            Text(source.bookSourceUrl)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(problemText(for: source))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if !sourceStats.problemSources.isEmpty {
                Section("快捷操作") {
                    Button(role: .destructive) {
                        let problemURLs = Set(sourceStats.problemSources.map(\.bookSourceUrl))
                        appState.sourceStore.setEnabled(false, for: problemURLs)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Label("一键禁用问题书源 (\(sourceStats.problemSources.count))", systemImage: "xmark.circle")
                    }

                    Button {
                        let allURLs = Set(appState.sourceStore.sources.map(\.bookSourceUrl))
                        appState.sourceStore.setEnabled(true, for: allURLs)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Label("一键启用全部书源", systemImage: "checkmark.circle")
                    }
                }
            }

            Section("说明") {
                Text("规则体检自动识别缺搜索地址、目录规则或正文规则的书源，并提供一键禁用，避免在多源聚合搜索时浪费网络请求。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("规则体检")
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func problemText(for source: BookSource) -> String {
        var problems: [String] = []
        let hasSearch = !(source.searchUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasExplore = !(source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Explore-only sources (365小说, 台湾小说 …) are legitimate in Legado:
        // they are browsed from 发现 instead of search.  Reporting them as
        // "缺搜索地址" made the one-tap cleanup disable ~20 working sources.
        if !hasSearch && !hasExplore {
            problems.append("缺搜索地址")
        }
        if source.ruleToc == nil {
            problems.append("缺目录规则")
        }
        if source.ruleContent == nil {
            problems.append("缺正文规则")
        }
        return problems.joined(separator: " / ")
    }
}

struct PurifyRulesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newRule = ""
    @State private var importText = ""
    @State private var importUrl = ""
    @State private var selectedPresetIDs: Set<String> = []
    @State private var previewText = "正文第一段\n请收藏本站，最新网址 example.com\n广告内容"
    @State private var message: String?
    @State private var urlMessage: String?
    @State private var isDownloadingRules = false

    var body: some View {
        List {
            Section("新增规则") {
                TextField("正则或 规则##替换文本", text: $newRule)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("添加") {
                    appState.purifyRuleStore.add(newRule)
                    newRule = ""
                }
                .disabled(newRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("批量导入") {
                TextEditor(text: $importText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 120)
                Button("按行导入") {
                    let count = appState.purifyRuleStore.importLines(importText)
                    importText = ""
                    message = "已导入 \(count) 条净化规则"
                }
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("URL 导入") {
                TextField("请输入净化规则的 URL 地址", text: $importUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button(isDownloadingRules ? "正在下载..." : "从 URL 导入") {
                    Task { await importRulesFromUrl() }
                }
                .disabled(importUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDownloadingRules)
                if let urlMessage {
                    Text(urlMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("推荐预设") {
                Text("预设只作为起点导入，后续仍可逐条关闭或删除。导入会自动跳过已存在规则。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(PurifyRulePreset.builtIn) { preset in
                    let isFullyImported = preset.patterns.allSatisfy {
                        appState.purifyRuleStore.containsPattern($0)
                    }
                    Toggle(isOn: Binding(
                        get: { selectedPresetIDs.contains(preset.id) },
                        set: { isSelected in
                            if isSelected {
                                selectedPresetIDs.insert(preset.id)
                            } else {
                                selectedPresetIDs.remove(preset.id)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(preset.title)
                                if isFullyImported {
                                    Text("已导入")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(preset.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isFullyImported)
                }

                Button("导入选中预设") {
                    let imported = appState.purifyRuleStore.importPatterns(selectedPresetPatterns)
                    selectedPresetIDs.removeAll()
                    message = "已导入 \(imported) 条预设规则"
                }
                .disabled(selectedPresetPatterns.isEmpty)
            }

            Section("快速管理") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(appState.purifyRuleStore.enabledPatterns.count) / \(appState.purifyRuleStore.rules.count) 条启用")
                        Text("关闭规则会保留内容，便于排查误删正文。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Button("启用全部") {
                        appState.purifyRuleStore.setAllEnabled(true)
                    }
                    .disabled(appState.purifyRuleStore.rules.isEmpty)

                    Button("停用全部") {
                        appState.purifyRuleStore.setAllEnabled(false)
                    }
                    .disabled(appState.purifyRuleStore.rules.isEmpty)
                }
            }

            Section("规则测试") {
                TextEditor(text: $previewText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 90)
                VStack(alignment: .leading, spacing: 6) {
                    Text("净化结果")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(appState.purifyRuleStore.preview(text: previewText))
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            Section("已启用规则") {
                if appState.purifyRuleStore.rules.isEmpty {
                    Text("暂无净化规则。规则会在正文解析后执行，用于删除广告、站点尾巴或固定乱码片段。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.purifyRuleStore.rules) { rule in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { rule.enabled },
                                set: { appState.purifyRuleStore.setEnabled($0, ruleID: rule.id) }
                            )) {
                                Text(rule.pattern)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(3)
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                appState.purifyRuleStore.remove(ruleID: rule.id)
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { dismissKeyboard() }
            }
        }
        .navigationTitle("净化规则")
    }

    private var selectedPresetPatterns: [String] {
        PurifyRulePreset.builtIn
            .filter { selectedPresetIDs.contains($0.id) }
            .flatMap(\.patterns)
            .filter { !appState.purifyRuleStore.containsPattern($0) }
    }

    private func importRulesFromUrl() async {
        let trimmed = importUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            urlMessage = "无效的 URL 地址"
            return
        }

        isDownloadingRules = true
        urlMessage = "正在拉取规则..."

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                isDownloadingRules = false
                urlMessage = "下载失败：服务器响应错误"
                return
            }

            guard let text = String(data: data, encoding: .utf8) else {
                isDownloadingRules = false
                urlMessage = "解码失败：内容不是有效的 UTF-8 文本"
                return
            }

            let count = appState.purifyRuleStore.importLines(text)
            importUrl = ""
            isDownloadingRules = false
            urlMessage = "已成功从网络导入 \(count) 条净化规则"
        } catch {
            isDownloadingRules = false
            urlMessage = "下载失败：\(error.localizedDescription)"
        }
    }
}

private struct RuleHealthStats {
    let total: Int
    let enabled: Int
    let searchable: Int
    let readable: Int
    let problemSources: [BookSource]

    init(sources: [BookSource]) {
        total = sources.count
        enabled = sources.filter(\.enabled).count
        searchable = sources.filter { Self.canSearch($0) || Self.canDiscover($0) }.count
        readable = sources.filter { $0.ruleContent != nil }.count
        problemSources = sources.filter {
            (!Self.canSearch($0) && !Self.canDiscover($0)) || $0.ruleToc == nil || $0.ruleContent == nil
        }
    }

    /// 发现页专用源在 Legado 里完全合法：`searchUrl` 为空但 `exploreUrl` 有分类。
    static func canSearch(_ source: BookSource) -> Bool {
        !(source.searchUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canDiscover(_ source: BookSource) -> Bool {
        !(source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct AboutReadView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppTheme.accent.opacity(0.95),
                                        Color(red: 0.46, green: 0.54, blue: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .overlay {
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 25, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .shadow(color: AppTheme.accent.opacity(0.25), radius: 10, x: 0, y: 6)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("纸间 (InPage)")
                                .font(.title2.bold())
                            Text("\(AppVersion.displayString) · 源流引擎驱动")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }

                    Text("纸间，取自「字里行间」。\n\n我们想做的，只是一只安静的书匣：没有推送，没有催促，也不替你决定下一本读什么。打开一本书，剩下的交给文字。\n\n它支持 Legado 格式的 JSON 书源，也能读本地 TXT 与 EPUB。字号、行距、翻页方式、底色都可以慢慢调成你习惯的样子；读到哪里，合上再打开，还是那一页。\n\n纸间还在打磨。如果你遇到问题，或者想要某个功能，欢迎告诉我们。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }

            Section("合规与条款") {
                NavigationLink {
                    PrivacyLegalHubView()
                } label: {
                    Label("隐私政策与法律条款中心", systemImage: "shield.checkered")
                }
                NavigationLink {
                    PrivacyPolicyDetailView()
                } label: {
                    Label("隐私政策 (Privacy Policy)", systemImage: "hand.raised")
                }
                NavigationLink {
                    UserAgreementDetailView()
                } label: {
                    Label("用户服务协议 (Terms)", systemImage: "doc.text")
                }
                NavigationLink {
                    OpenSourceLicensesDetailView()
                } label: {
                    Label("开源许可与致谢 (Licenses)", systemImage: "curlybraces")
                }
            }

            Section("致谢与声明") {
                Text("感谢 Legado 与源阅读开源社区的无私奉献。\n\n免责声明：本应用为本地阅读与书源解析工具，本身不提供、不存储任何网络图书或数字版权内容。所有网络书源由用户自行添加或抓取自公开站点，相关内容版权归原作者所有。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于纸间")
    }
}
