import SwiftUI
import UIKit

/// A bounded snapshot: incoming events cannot keep expanding or shifting the
/// settings screen while the user is reading/copying an earlier diagnostic.
struct RecentDiagnosticsView: View {
    let events: [DiagnosticEvent]
    @State private var copied = false
    private var snapshot: [DiagnosticEvent] { Array(events.prefix(100)) }

    var body: some View {
        List {
            Section {
                Button {
                    UIPasteboard.general.string = snapshot.map(Self.export).joined(separator: "\n\n")
                    copied = true
                } label: { Label(copied ? "已复制" : "复制最近 100 条诊断", systemImage: "doc.on.doc") }
                if snapshot.isEmpty { Text("暂无诊断").foregroundStyle(.secondary) }
            }
            .listRowBackground(AppThemeRowSurface())
            ForEach(snapshot) { event in
                NavigationLink {
                    ScrollView {
                        Text(Self.export(event)).font(.system(.body, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                    }
                    .pageBackground()
                    .navigationTitle("诊断详情")
                    .toolbar {
                        Button("复制") { UIPasteboard.general.string = Self.export(event) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("[\(event.stage)] \(SourceDiagnosticRedactor.recentSummary(event))")
                            .font(.subheadline).lineLimit(2)
                        Text(event.date, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .pageBackground()
        .navigationTitle("最近诊断")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func export(_ event: DiagnosticEvent) -> String {
        let details = SourceDiagnosticRedactor.recentDetails(event.details)
            .sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        let message = SourceDiagnosticRedactor.recentSummary(event)
        return "\(event.date.formatted()) [\(event.level.rawValue)] [\(event.stage)]\n\(message)\n\(details)"
    }
}
