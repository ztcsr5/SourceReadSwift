from pathlib import Path
R=Path(__file__).resolve().parents[2]
p=R/'SourceReadSwift/Features/Settings/SettingsView.swift'
s=p.read_text(encoding='utf8')
start=s.index('                Section {\n                    let perf =')
end=s.index('\n                Section("诊断")',start)
perf=s[start:end]
new='''import SwiftUI

/// Keep the full diagnostics, but don't spend the settings landing page on
/// six mostly-zero development counters and a long explanatory footer.
struct ReaderPerformanceDiagnosticsView: View {
    @State private var perfRefreshToken = UUID()

    var body: some View {
        List {
'''+perf+'''
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("阅读器性能")
        .navigationBarTitleDisplayMode(.inline)
    }
}
'''
(R/'SourceReadSwift/Features/Settings/ReaderPerformanceDiagnosticsView.swift').write_text(new,encoding='utf8')
s=s[:start]+s[end:]
s=s.replace('    /// 清零采样后强制刷新诊断区。\n    @State private var perfRefreshToken = UUID()\n','')
s=s.replace('''                Section {
                    NavigationLink {
                        AppearanceSettingsView()''','''                Section("阅读与外观") {
                    NavigationLink {
                        AppearanceSettingsView()''',1)
for header in ['排版与字体','语音朗读']:
    old='''                }

                Section("'''+header+'''") {
'''
    assert old in s,header
    s=s.replace(old,'',1)
s=s.replace('Section("交互与反馈")','Section("交互与性能")',1)
s=s.replace('''                }

                Section("并发与性能") {
''','',1)
s=s.replace('''                Section("诊断") {
''','''                Section("诊断") {
                    NavigationLink {
                        ReaderPerformanceDiagnosticsView().hideRootTabBar()
                    } label: {
                        Label("阅读器性能", systemImage: "speedometer")
                    }
''',1)
s=s.replace('.navigationBarTitleDisplayMode(.large)','.navigationBarTitleDisplayMode(.inline)',1)
s=s.replace('''            HStack(spacing: 16) {
                Image(systemName: "book.closed.fill")''','''            HStack(spacing: 12) {
                Image(systemName: "book.closed.fill")''',1)
s=s.replace('.font(.system(size: 30, weight: .light))','.font(.system(size: 25, weight: .light))',1)
s=s.replace('.frame(width: 48, height: 56)','.frame(width: 36, height: 40)',1)
s=s.replace('''                    Text("纸间").font(.system(size: 25, weight: .semibold, design: .serif))
                    Text("把时间留给阅读").font(.subheadline).foregroundStyle(.secondary)
                    Text(AppVersion.fullDisplayString).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)''','''                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("纸间").font(.title3.weight(.semibold))
                        Text(AppVersion.fullDisplayString).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                    Text("把时间留给阅读").font(.caption).foregroundStyle(.secondary)''',1)
s=s.replace('.padding(.vertical, 10)\n            .listRowBackground(Color.clear)','.padding(.vertical, 2)\n            .listRowBackground(Color.clear)',1)
p.write_text(s,encoding='utf8')

p=R/'SourceReadSwift/Features/SourceManager/SourceManagerView.swift'
s=p.read_text(encoding='utf8')
a=s.index('    private var webServiceCard: some View {')
b=s.index('    private func sourceActionTile(',a)
old=s[a:b]
actions=old[old.index('                Button {'):old.index('            Text("支持 JSON')]
# Last brace closes the original grid, not an action.
assert actions.endswith('            }\n')
actions=actions[:-len('            }\n')]
s=s[:a]+'''    private var webServiceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("书源 \\(sourceCounts.books) · 仓库 \\(sourceCounts.catalogs) · RSS \\(sourceCounts.rss)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { sourceQuickActions }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 6) { sourceQuickActions }
            }
            .buttonStyle(.plain)
            DisclosureGroup("格式与检测说明") {
                Text("支持 JSON、URL、阅读分享链接、仓库、RSS，以及搜索 → 详情 → 目录 → 正文全链路测试。")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(AppLayout.cardInset)
        .glassPanel(cornerRadius: AppTheme.cardRadius, material: .thinMaterial, strokeOpacity: 0.08, shadowOpacity: 0.04)
    }

    @ViewBuilder private var sourceQuickActions: some View {
'''+actions+'''    }

'''+s[b:]
s=s.replace('''        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10)''','''        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTapTarget, alignment: .leading)
        .background(tint.opacity(0.10)''',1)
p.write_text(s,encoding='utf8')

p=R/'SourceReadSwift/Features/Discover/SourceWritingView.swift'
s=p.read_text(encoding='utf8')
# Restrict changes to the view, never touch the HTTP server implementation.
head,tail=s.split('// MARK: - HTTP Server Implementation',1)
head=head.replace('spacing: 24','spacing: AppLayout.sectionGap').replace('.padding(20)','.padding(AppLayout.cardInset)').replace('minHeight: 100','minHeight: 64')
p.write_text(head+'// MARK: - HTTP Server Implementation'+tail,encoding='utf8')
for file in ['project.yml','SourceReadSwift/Shared/AppVersion.swift']:
    p=R/file;s=p.read_text(encoding='utf8').replace('1.1.4','1.1.5')
    if file=='project.yml':s=s.replace('CURRENT_PROJECT_VERSION: 125','CURRENT_PROJECT_VERSION: 126')
    else:s=s.replace('build = "125"','build = "126"')
    p.write_text(s,encoding='utf8')
print('Compact home/settings/source tools/details/shared cards; reader body untouched.')
