import SwiftUI

struct ReaderHighlightRulesView: View {
    var bookTitle: String = ""
    var sourceURL: String = ""
    var isNight: Bool = false

    @ObservedObject private var store = ReaderHighlightRuleStore.shared
    @State private var editingDraft: ReaderHighlightRule?
    @State private var isCreatingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            samplePreviewStrip
            if store.rules.isEmpty {
                emptyRulesCard
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(store.rules) { rule in
                        ruleRow(rule)
                    }
                }
            }
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !hasAllBuiltInTemplates {
                Button("恢复内置示例规则") {
                    store.restoreDefaultTemplates()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.accent)
            }
        }
        .sheet(isPresented: $isCreatingNew) {
            ReaderHighlightRuleEditorSheet(
                initialRule: ReaderHighlightRule(name: "", pattern: ""),
                isNew: true,
                bookTitle: bookTitle,
                sourceURL: sourceURL,
                isNight: isNight
            ) { saved in
                store.addOrUpdate(saved)
            }
        }
        .sheet(item: $editingDraft) { draft in
            ReaderHighlightRuleEditorSheet(
                initialRule: draft,
                isNew: false,
                bookTitle: bookTitle,
                sourceURL: sourceURL,
                isNight: isNight,
                onSave: { saved in
                    store.addOrUpdate(saved)
                },
                onDelete: {
                    store.remove(ruleID: draft.id)
                }
            )
        }
    }

    private var hasAllBuiltInTemplates: Bool {
        ReaderHighlightRule.builtInTemplates.allSatisfy { tpl in
            store.rules.contains(where: { $0.id == tpl.id })
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("关键词与正则高亮")
                    .font(.subheadline.weight(.semibold))
                Text("纯色块着色，无下划线；滚屏与分页即时生效")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isCreatingNew = true
            } label: {
                Label("添加规则", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(AppTheme.accent.opacity(0.14), in: Capsule())
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reader.highlights.add")
        }
    }

    private var samplePreviewStrip: some View {
        let sampleText = "顾清寒道：「此去经年，勿忘今日之约。」【修为突破】青霜剑微微一震。"
        let active = store.activeRules(bookTitle: bookTitle, sourceURL: sourceURL)
        var attributed = AttributedString(sampleText)
        ReaderHighlightMatcher.applyHighlights(
            to: &attributed,
            sourceText: sampleText,
            rules: active,
            boldFont: .system(size: 13.5, weight: .semibold),
            isNight: isNight
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("效果示例")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("已启用 \(active.count) 条")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(attributed)
                .font(.system(size: 13.5))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyRulesCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "highlighter")
                .foregroundStyle(.secondary)
            Text("暂无高亮规则，点右上角“添加规则”创建人名、对话或提示高亮。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ruleRow(_ rule: ReaderHighlightRule) -> some View {
        let inContext = rule.matchesContext(bookTitle: bookTitle, sourceURL: sourceURL)
        return HStack(spacing: 10) {
            Button {
                editingDraft = rule
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(rule.resolvedBackgroundColor(isNight: isNight))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Text(rule.isBold ? "B" : "A")
                                .font(.system(size: 12, weight: rule.isBold ? .bold : .medium))
                                .foregroundStyle(rule.resolvedForegroundColor(isNight: isNight) ?? .primary)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.6)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(rule.name.isEmpty ? rule.pattern : rule.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if rule.isRegex {
                                badge("正则")
                            }
                            if rule.scopeKind != .all {
                                badge(inContext ? rule.scopeKind.title : "\(rule.scopeKind.title)·未命中")
                            }
                        }
                        Text(rule.pattern)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { store.setEnabled($0, ruleID: rule.id) }
            ))
            .labelsHidden()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button("编辑规则") { editingDraft = rule }
            Button("删除规则", role: .destructive) { store.remove(ruleID: rule.id) }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(.primary.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

private struct ReaderHighlightRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ReaderHighlightRule
    @State private var usesCustomBackground: Bool
    @State private var usesCustomForeground: Bool
    @State private var customBgColor: Color
    @State private var customFgColor: Color

    let isNew: Bool
    let bookTitle: String
    let sourceURL: String
    let isNight: Bool
    let onSave: (ReaderHighlightRule) -> Void
    var onDelete: (() -> Void)? = nil

    init(
        initialRule: ReaderHighlightRule,
        isNew: Bool,
        bookTitle: String,
        sourceURL: String,
        isNight: Bool,
        onSave: @escaping (ReaderHighlightRule) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: initialRule)
        let hasBg = ReaderHighlightRule.parseHexUInt32(initialRule.customBackgroundHex) != nil
        let hasFg = ReaderHighlightRule.parseHexUInt32(initialRule.customForegroundHex) != nil
        _usesCustomBackground = State(initialValue: hasBg)
        _usesCustomForeground = State(initialValue: hasFg)
        _customBgColor = State(initialValue: Color(hex: initialRule.resolvedBackgroundHexValue()))
        _customFgColor = State(initialValue: Color(hex: initialRule.resolvedForegroundHexValue(isNight: isNight) ?? initialRule.preset.foregroundHexValue(isNight: isNight)))
        self.isNew = isNew
        self.bookTitle = bookTitle
        self.sourceURL = sourceURL
        self.isNight = isNight
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var validationError: ReaderHighlightRuleError? {
        ReaderHighlightMatcher.validationError(pattern: draft.pattern, isRegex: draft.isRegex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("实时预览") {
                    previewBanner
                }

                Section("匹配规则") {
                    TextField("规则名称（如：对话、主角名）", text: $draft.name)
                    TextField(draft.isRegex ? "正则表达式（例如：【[^】]+】）" : "关键词（例如：青霜剑）", text: $draft.pattern)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(.subheadline, design: draft.isRegex ? .monospaced : .default))
                    Toggle("使用正则表达式", isOn: $draft.isRegex)
                    Toggle("区分大小写", isOn: $draft.caseSensitive)
                    if let validationError {
                        Text(validationError.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("着色样式（纯色背景，无下划线）") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ReaderHighlightPreset.allCases) { preset in
                                Button {
                                    draft.preset = preset
                                    usesCustomBackground = false
                                    usesCustomForeground = false
                                    draft.customBackgroundHex = nil
                                    draft.customForegroundHex = nil
                                } label: {
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(preset.swatchColor(isNight: isNight))
                                            .frame(width: 44, height: 28)
                                            .overlay {
                                                Text("字")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(preset.swatchTextColor(isNight: isNight))
                                            }
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(
                                                        !usesCustomBackground && draft.preset == preset
                                                            ? AppTheme.accent
                                                            : Color.primary.opacity(0.12),
                                                        lineWidth: !usesCustomBackground && draft.preset == preset ? 2 : 0.8
                                                    )
                                            }
                                        Text(preset.title)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Toggle("文字跟随主题着色", isOn: $draft.tintForeground)
                    Toggle("匹配文字略微加粗", isOn: $draft.isBold)

                    Toggle("自定背景底色", isOn: $usesCustomBackground)
                    if usesCustomBackground {
                        ColorPicker("选择底色", selection: $customBgColor, supportsOpacity: false)
                    }
                    Toggle("自定文字颜色", isOn: $usesCustomForeground)
                    if usesCustomForeground {
                        ColorPicker("选择字色", selection: $customFgColor, supportsOpacity: false)
                    }
                }

                Section("生效范围") {
                    Picker("作用范围", selection: $draft.scopeKind) {
                        ForEach(ReaderHighlightScopeKind.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    if draft.scopeKind != .all {
                        HStack {
                            TextField(
                                draft.scopeKind == .bookTitle ? "书名关键词" : "书源地址或名称关键词",
                                text: $draft.scopeKeyword
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            if draft.scopeKind == .bookTitle, !bookTitle.isEmpty {
                                Button("填入当前书名") { draft.scopeKeyword = bookTitle }
                                    .font(.caption)
                            } else if draft.scopeKind == .sourceURL, !sourceURL.isEmpty {
                                Button("填入当前书源") { draft.scopeKeyword = sourceURL }
                                    .font(.caption)
                            }
                        }
                    }
                }

                if !isNew, let onDelete {
                    Section {
                        Button("删除此规则", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "新建高亮规则" : "编辑高亮规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        commitAndDismiss()
                    }
                    .disabled(validationError != nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var previewDraft: ReaderHighlightRule {
        var copy = draft
        copy.enabled = true
        copy.customBackgroundHex = usesCustomBackground ? AppTheme.hex(customBgColor) : nil
        copy.customForegroundHex = usesCustomForeground ? AppTheme.hex(customFgColor) : nil
        return copy
    }

    private var previewBanner: some View {
        let activeRule = previewDraft
        let sample = activeRule.pattern.isEmpty
            ? "示例文本：「此去经年」【系统提示】"
            : (activeRule.isRegex
                ? "示例：顾清寒道：「此去经年」【系统提示】"
                : "这段文字包含 \(activeRule.pattern) ，呈现非下划线底色高亮。")
        var attr = AttributedString(sample)
        ReaderHighlightMatcher.applyHighlights(
            to: &attr,
            sourceText: sample,
            rules: [activeRule],
            boldFont: .body.weight(.semibold),
            isNight: isNight
        )
        return Text(attr)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func commitAndDismiss() {
        var finalRule = previewDraft
        if isNew {
            finalRule.enabled = true
        } else {
            finalRule.enabled = draft.enabled
        }
        onSave(finalRule)
        dismiss()
    }
}
