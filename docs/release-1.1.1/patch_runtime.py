from pathlib import Path
R=Path(__file__).resolve().parents[2]
def edit(n,f):
 p=R/n;s=p.read_text(encoding='utf-8');p.write_text(f(s),encoding='utf-8')
def once(s,a,b):
 assert s.count(a)==1,(a[:80],s.count(a));return s.replace(a,b,1)
def diagnostic(s):
 a=s.index('        (engine as? SourceWebViewFallbackControllable)?.allowWebViewFallback = false')
 s=s[:a]+'''        await SourceRequestContext.$isDiagnostic.withValue(true) {
            await runIsolated(source: source, keyword: keyword, deepCheck: deepCheck, page: page, timeout: timeout)
        }
    }

    private func runIsolated(source: BookSource, keyword: String, deepCheck: Bool,
                             page: Int, timeout: TimeInterval) async -> SourceDiagnosticReport {
'''+s[a:].replace('        (engine as? SourceWebViewFallbackControllable)?.allowWebViewFallback = false\n','',1)
 return s
edit('SourceReadSwift/Core/Rules/SourceBatchDiagnosticRunner.swift',diagnostic)
edit('SourceReadSwift/Core/Engine/SourceEngine.swift',lambda s:once(s,'            return _allowWebViewFallback','            return _allowWebViewFallback && !SourceRequestContext.isDiagnostic'))
# Keep TOC encodes off the foreground path, and make write/invalidate ordered.
def toc(s):
 s=once(s,'    private let fileManager: FileManager','    private static let writer = DispatchQueue(label: "BookTOCache.writer", qos: .utility)\n    private let fileManager: FileManager')
 s=once(s,'        try? fileManager.removeItem(at: url)','        let manager = fileManager\n        Self.writer.async { try? manager.removeItem(at: url) }')
 s=once(s,'              let data = try? Data(contentsOf: url) else { return nil }','              let data = Self.writer.sync(execute: { try? Data(contentsOf: url) }) else { return nil }')
 a=s.index('        let encoder = JSONEncoder()');b=s.index('\n    }',a)
 s=s[:a]+'''        let fileManager = self.fileManager
        Self.writer.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(persisted) else { return }
            try? AppStorageDirectory.safeWrite(data, to: url, fileManager: fileManager)
        }'''+s[b:];return s
edit('SourceReadSwift/Core/Storage/BookTOCacheStore.swift',toc)
def root(s):
 s=once(s,'        return Group {\n            switch selectedTab {','        return navigationContent\n        .frame(maxWidth: .infinity, maxHeight: .infinity)\n        .safeAreaInset(edge: .bottom, spacing: 0) {\n            if !usesNativeTabs, !appState.isTabChromeHidden {\n                VStack(spacing: 8) {\n                    if audioCoordinator.currentBook != nil { miniAudioPlayerBar }\n                    customTabBar\n                }\n            }\n        }\n        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: appState.isTabChromeHidden)\n        .tint(AppTheme.accent)\n        .onChange(of: selectedTab) { _ in dismissKeyboard() }\n        .sheet(isPresented: $showFullAudioPlayer) { AudioBookPlayerView() }\n        .sheet(item: verificationRequestBinding) { request in\n            VerificationCodeSheet(request: request,\n                onSubmit: { verificationCoordinator.submit(id: request.id, code: $0) },\n                onCancel: { verificationCoordinator.cancel(id: request.id) })\n        }\n    }\n\n    private var usesNativeTabs: Bool {\n        #if compiler(>=6.2)\n        if #available(iOS 26.0, *) { return true }\n        #endif\n        return false\n    }\n\n    @ViewBuilder private var navigationContent: some View {\n        #if compiler(>=6.2)\n        if #available(iOS 26.0, *) {\n            TabView(selection: $selectedTab) {\n                BookshelfView().tabItem { Label("主页", systemImage: "house") }.tag(0)\n                DiscoverView(viewModel: appState.discoverViewModel).tabItem { Label("发现", systemImage: "square.grid.2x2") }.tag(1)\n                SettingsView().tabItem { Label("设置", systemImage: "gearshape") }.tag(2)\n            }\n            .toolbar(appState.isTabChromeHidden ? .hidden : .visible, for: .tabBar)\n            .tabBarMinimizeBehavior(.onScrollDown)\n            .tabViewBottomAccessory {\n                if audioCoordinator.currentBook != nil, !appState.isTabChromeHidden { miniAudioPlayerBar }\n            }\n        } else {\n            legacyNavigationContent\n        }\n        #else\n        legacyNavigationContent\n        #endif\n    }\n\n    private var legacyNavigationContent: some View {\n        Group {\n            switch selectedTab {')
 a=s.index('        .frame(maxWidth: .infinity, maxHeight: .infinity)',s.index('    private var legacyNavigationContent'))
 b=s.index('    /// Unit tests drive',a)
 s=s[:a]+'    }\n\n'+s[b:]
 return s
edit('SourceReadSwift/App/RootTabView.swift',root)
edit('.github/workflows/unsigned-ipa.yml',lambda s:once(s,'    timeout-minutes: 30','    timeout-minutes: 30\n    env:\n      DEVELOPER_DIR: /Applications/Xcode_26.0.1.app/Contents/Developer'))
print('native iOS26 tabs (iOS16 legacy), probe isolation and TOC writer patched')
