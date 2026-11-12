import SwiftUI

/// TXT 目录规则库的编辑界面。
///
/// 布局与项目现有设置页保持一致（`List` + `AppThemeRowSurface`），
/// 让用户能看到每条规则的开关、优先级和正则本身，并当场试跑。
struct TxtChapterRulesView: View {
    @State private var library = TxtChapterRuleLibrary.load()
    @State private var draftName = ""
    @State private var draftPattern = ""
    @State private var draftPriority = 200
    @State private var probeLine = "第一章 潜龙勿用"
    @State private var editingID: UUID?
    @State private var pendingDelete: TxtChapterRule?

    private var ordered: [TxtChapterRule] {
        library.rules.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("启用自定义目录规则", isOn: Binding(
                    get: { library.isEnabled },
                    set: { library.isEnabled = $0; persist() }))
                Text("关闭时使用内置识别（第X章 / Chapter / 数字序号等）。开启后只有下列已启用规则参与判断，关闭某条规则会立刻改变导入结果。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("总开关") }
            .listRowBackground(AppThemeRowSurface())

            Section {
                TextField("试跑一行标题", text: $probeLine)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Text("判断结果")
                    Spacer()
                    Text(probeVerdict)
                        .foregroundStyle(probeColor)
                        .font(.subheadline.weight(.semibold))
                }
            } header: { Text("即时试跑") } footer: {
                Text("试跑使用与导入完全相同的匹配顺序：优先级从高到低，第一条命中的规则决定结果。")
            }
            .listRowBackground(AppThemeRowSurface())

            Section {
                ForEach(ordered) { rule in
                    ruleRow(rule)
                }
                .onDelete(perform: delete)
            } header: { Text("规则（按优先级降序）") } footer: {
                Text("内置规则可以停用但不能删除；自定义规则左滑删除。拖动右侧把手可换行，优先级仍以数字为准。")
            }
            .listRowBackground(AppThemeRowSurface())

            Section {
                TextField("规则名称", text: $draftName)
                TextField("正则，例如 ^第\\s*[0-9一二三]+\\s*章.*$", text: $draftPattern)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                Stepper("优先级 \(draftPriority)", value: $draftPriority, in: 0...1000, step: 10)
                if let problem = draftProblem {
                    Text(problem.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("添加规则") { addDraft() }
                    .disabled(draftProblem != nil || draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: { Text("新增规则") }
            .listRowBackground(AppThemeRowSurface())

            Section {
                Button("恢复内置规则（全部停用）") {
                    library = .seeded
                    persist()
                }
                .foregroundStyle(.red)
            } footer: {
                Text("这会把规则恢复到出厂状态，并重新关闭总开关；不会影响书架与阅读进度。")
            }
            .listRowBackground(AppThemeRowSurface())
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("TXT 目录规则")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
        .confirmationDialog("删除规则「\(pendingDelete?.name ?? "")」？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let target = pendingDelete {
                    library.rules.removeAll { $0.id == target.id }
                    persist()
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: TxtChapterRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { setEnabled($0, for: rule) }))
                    .labelsHidden()
                Text(rule.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(rule.priority)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if rule.isBuiltIn {
                    Text("内置")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                }
            }
            Text(rule.pattern)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let problem = rule.patternProblem {
                Text(problem.message).font(.caption).foregroundStyle(.red)
            }
            Stepper("优先级 \(rule.priority)", value: Binding(
                get: { rule.priority },
                set: { setPriority($0, for: rule) }),
                in: 0...1000, step: 10)
                .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private var probeVerdict: String {
        let trimmed = probeLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "请输入一行" }
        guard library.isEnabled else { return "总开关关闭 · 用内置" }
        guard let answer = library.classify(trimmed) else { return "无有效规则 · 用内置" }
        return answer ? "识别为标题" : "视为正文"
    }

    private var probeColor: Color {
        guard library.isEnabled, let answer = library.classify(probeLine.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .secondary
        }
        return answer ? AppTheme.accent : .secondary
    }

    private var draftProblem: TxtChapterRule.PatternProblem? {
        TxtChapterRule(name: draftName, pattern: draftPattern).patternProblem
    }

    private func addDraft() {
        let rule = TxtChapterRule(name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
                                  pattern: draftPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                                  priority: draftPriority)
        guard rule.isValid else { return }
        library.rules.append(rule)
        persist()
        draftName = ""; draftPattern = ""; draftPriority = 200
    }

    private func setEnabled(_ enabled: Bool, for rule: TxtChapterRule) {
        guard let index = library.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        library.rules[index].isEnabled = enabled
        persist()
    }

    private func setPriority(_ priority: Int, for rule: TxtChapterRule) {
        guard let index = library.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        library.rules[index].priority = priority
        persist()
    }

    private func delete(at offsets: IndexSet) {
        let visible = ordered
        let targets = offsets.map { visible[$0] }.filter { !$0.isBuiltIn }
        guard !targets.isEmpty else { return }
        library.rules.removeAll { rule in targets.contains(where: { $0.id == rule.id }) }
        persist()
    }

    private func persist() {
        library.save()
        // Import reads the store through `LocalTextBookParser`'s default
        // argument, so the new rules apply to the next import without a relaunch.
    }
}
