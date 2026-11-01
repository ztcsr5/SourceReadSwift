import SwiftUI

enum AIGeneratedSourceDecoder {
    static func decode(_ text: String) throws -> BookSource {
        guard text.utf8.count <= 1_000_000,
              let json = SourceStore.extractFirstJSONValueStatic(from: text),
              let data = json.data(using: .utf8) else { throw AIChatFailure.invalidResponse }
        let decoder = JSONDecoder()
        let source: BookSource
        if let array = try? decoder.decode([BookSource].self, from: data), array.count == 1 { source = array[0] }
        else { source = try decoder.decode(BookSource.self, from: data) }
        guard !source.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: source.bookSourceUrl), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil,
              source.ruleToc != nil, source.ruleContent != nil else { throw AIChatFailure.invalidResponse }
        return source
    }
}

struct AIGeneratedSourceReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var json: String
    @State private var keyword = ""
    @State private var output = ""
    @State private var testedJSON: String?
    @State private var working = false
    @State private var confirmTest = false
    @State private var confirmImport = false
    @State private var worker: Task<Void, Never>?
    init(text: String) { _json = State(initialValue: SourceStore.extractFirstJSONValueStatic(from: text) ?? text) }

    var body: some View {
        NavigationStack {
            Form {
                Section("先复核，再测试") {
                    Text("AI 输出只是建议。测试会访问书源配置的站点并执行解析规则/JS，可能使用本机该站点会话；请先检查地址和脚本。不经过 AI 接口转发。一次只复核一个源。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $json).font(.system(.footnote, design: .monospaced)).frame(minHeight: 220)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("真实搜书测试关键词", text: $keyword)
                    Button(working ? "正在测试…" : "复核完成，联网测试") { confirmTest = true }
                        .disabled(working || keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if working { Button("停止测试") { worker?.cancel(); working = false } }
                    if !output.isEmpty { Text(output).font(.caption).textSelection(.enabled) }
                }
                .listRowBackground(AppThemeRowSurface())
                Section {
                    Button("导入已测试书源") { confirmImport = true }
                        .disabled(testedJSON != json || working)
                    Text("同 bookSourceUrl 会覆盖旧源。修改 JSON 或关键词将使测试结果失效；无搜索能力的源请复制到书源管理中手工验证。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(AppThemeRowSurface())
            }
            .scrollDismissesKeyboard(.interactively)
            .pageBackground()
            .navigationTitle("AI 书源复核").navigationBarTitleDisplayMode(.inline)
            .onChange(of: json) { _ in invalidate() }
            .onChange(of: keyword) { _ in invalidate() }
            .onDisappear { worker?.cancel() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("复制 JSON") { UIPasteboard.general.string = json } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { dismissKeyboard() } }
            }
            .confirmationDialog("已复核站点和脚本，开始真实联网测试？", isPresented: $confirmTest, titleVisibility: .visible) {
                Button("开始测试") { test() }
            }
            .confirmationDialog("确认导入？相同 URL 的书源会被替换。", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("确认导入") { importSource() }
            }
        }
    }

    private func invalidate() { worker?.cancel(); working = false; testedJSON = nil; output = "内容已变更，需要重新测试。" }

    private func test() {
        let captured = json, query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let source = try AIGeneratedSourceDecoder.decode(captured)
            guard !(source.searchUrl ?? "").isEmpty else { output = "此源未提供搜索协议；请复制到书源管理中手工验证目录/正文，不会伪装搜索成功。"; return }
            working = true; testedJSON = nil; output = "正在测试搜索 → 详情 → 目录 → 正文…"
            worker = Task { @MainActor in
                let report = await appState.engine.runPipelineReport(source: source, keyword: query, page: 1, timeout: 10)
                guard !Task.isCancelled, captured == json, query == keyword.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                working = false
                output = report.result.steps.map { "\($0.status == .passed ? "PASS" : "检查") \($0.stage.title)：\($0.responseSummary ?? $0.failureClassification ?? "无摘要")" }.joined(separator: "\n")
                if report.isSuccess { testedJSON = captured; output += "\n完整链路通过，尚未导入。" }
                else { output += "\n测试未通过，不允许直接覆盖旧源。" }
            }
        } catch { working = false; output = "JSON 不是有效的单个小说书源，需包含名称、HTTP(S)地址、目录和正文规则。" }
    }

    private func importSource() {
        guard testedJSON == json, !working else { return }
        do { let source = try AIGeneratedSourceDecoder.decode(json); try appState.sourceStore.importSources([source]); dismiss() }
        catch { output = "导入失败：\(error.localizedDescription)" }
    }
}
