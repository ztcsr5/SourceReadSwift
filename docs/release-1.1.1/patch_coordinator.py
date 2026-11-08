from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=root/'SourceReadSwift/Core/Rules/SourceBatchCheckCoordinator.swift'
s=p.read_text(encoding='utf8')
s=s.replace('    private let reportFileName', '    private static let reportWriter = DispatchQueue(label: "SourceBatchCheck.reportWriter", qos: .utility)\n    private let reportFileName',1)
s=s.replace('        historyStore: SourceDiagnosticHistoryStore\n    ) {','        historyStore: SourceDiagnosticHistoryStore,\n        concurrency: Int = 8\n    ) {',1)
s=s.replace('                historyStore: historyStore\n','                historyStore: historyStore,\n                concurrency: min(max(concurrency, 1), 16)\n',1)
s=s.replace('    func stop() {\n','    func stop() {\n        activeSessionID = UUID()\n',1)
s=s.replace('        historyStore: SourceDiagnosticHistoryStore\n    ) async {\n        (engine as? SourceWebViewFallbackControllable)?.allowWebViewFallback = false\n        defer {\n            (engine as? SourceWebViewFallbackControllable)?.allowWebViewFallback = true\n        }','        historyStore: SourceDiagnosticHistoryStore,\n        concurrency: Int\n    ) async {',1)
a=s.index('        let concurrency = SandboxEnvironment.recommendedBatchConcurrency')
b=s.index('                    loopCount += 1',a)
s=s[:a]+'''        await withTaskGroup(of: BatchCheckOutcome.self) { group in
            var iterator = sources.makeIterator()
            func submit(_ source: BookSource) {
                group.addTask {
                    await SourceRequestContext.$isDiagnostic.withValue(true) {
                        await Self.evaluateSource(source: source, keyword: keyword,
                                                  engine: engine, deepCheck: deepCheck)
                    }
                }
            }
            for _ in 0..<min(concurrency, sources.count) {
                if let source = iterator.next() { submit(source) }
            }
            while let outcome = await group.next() {
                guard !Task.isCancelled, self.activeSessionID == sessionID else {
                    group.cancelAll()
                    return
                }
                // Refill before UI/history bookkeeping, without a batch barrier.
                if let source = iterator.next() { submit(source) }
''' +s[b:]
old='''                }
            }

            // Sync UI and release network cache per chunk
            syncUI()
            URLCache.shared.removeAllCachedResponses()
        }

        syncUI()'''
new='''            }
        }

        // A cancelled old run must never flush into its replacement session.
        guard !Task.isCancelled, activeSessionID == sessionID else { return }
        syncUI()'''
assert old in s;s=s.replace(old,new,1)
s=s.replace('        Task.detached(priority: .utility) {\n            do {\n                let encoder = JSONEncoder()','        Self.reportWriter.async {\n            do {\n                let encoder = JSONEncoder()',1)
s=s.replace('        guard FileManager.default.fileExists(atPath: url.path),\n              let data = try? Data(contentsOf: url),\n              let report = try? JSONDecoder().decode(SourceDiagnosticBatchReport.self, from: data) else {','        let decoder = JSONDecoder()\n        decoder.dateDecodingStrategy = .iso8601\n        guard let data = Self.reportWriter.sync(execute: { try? Data(contentsOf: url) }),\n              let report = try? decoder.decode(SourceDiagnosticBatchReport.self, from: data) else {',1)
p.write_text(s,encoding='utf8')
p=root/'SourceReadSwift/Features/SourceManager/SourceManagerView.swift';s=p.read_text(encoding='utf8')
s=s.replace('并发 \\(SandboxEnvironment.recommendedBatchConcurrency) 个','并发 \\(batchCheckConcurrency) 个',1)
s=s.replace('                                historyStore: appState.sourceDiagnosticHistoryStore\n','                                historyStore: appState.sourceDiagnosticHistoryStore,\n                                concurrency: batchCheckConcurrency\n',1)
p.write_text(s,encoding='utf8')
