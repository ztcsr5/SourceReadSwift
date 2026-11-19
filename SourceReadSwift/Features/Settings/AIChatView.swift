import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct AIChatRecapSeed: Identifiable, Equatable, Sendable {
    let id = UUID()
    let bookTitle: String
    let author: String
    let currentChapterIndex: Int
    let currentChapterTitle: String
    let readChaptersSummary: String

    static func buildPrompt(
        bookTitle: String,
        author: String,
        currentChapterIndex: Int,
        currentChapterTitle: String
    ) -> String {
        """
        请基于附件《\(bookTitle)》（作者：\(author)）截止「第 \(currentChapterIndex + 1) 章 · \(currentChapterTitle)」的已读章节正文，为我做一份【绝对无剧透】的前情提要：
        1. 严谨红线：只允许依据我已读到的上述章节内容总结，严禁剧透或推测第 \(currentChapterIndex + 2) 章及之后的任何后续剧情、伏笔揭晓或人物命运！
        2. 按「近期核心冲突」「关键人物关系与立场」「未解悬念（仅限已读范围）」分点梳理，控制在 350 字左右。
        """
    }
}

struct AIChatView: View {
    var recapSeed: AIChatRecapSeed? = nil

    @EnvironmentObject private var appState: AppState
    @AppStorage("settings.ai.configuration") private var storedConfiguration = Data()
    @AppStorage("settings.ai.profiles") private var storedProfiles = Data()
    @AppStorage("settings.ai.activeProfileID") private var activeProfileIDRaw = ""
    @AppStorage("settings.ai.assistant_mode") private var selectedModeRaw = "api"
    @StateObject private var session = AIChatSession()
    @State private var profiles: [AIChatProviderProfile] = []
    @State private var activeProfileID: UUID?
    @State private var input = ""
    @State private var attachments: [AIChatAttachment] = []
    @State private var showConfiguration = false
    @State private var showFiles = false
    @State private var showLibrary = false
    @State private var preparingAttachment = false
    @State private var attachmentTask: Task<Void, Never>?
    @State private var attachmentRevision = UUID()
    @State private var pending: AIChatSubmission?
    @State private var editing: AIChatAttachment?
    @State private var generatedSource: AIChatMessage?
    @State private var fullText: AIChatMessage?
    @State private var showClear = false
    @State private var didApplyRecapSeed = false
    @FocusState private var composing: Bool

    private var currentMode: AIAssistantMode {
        AIAssistantMode(rawValue: selectedModeRaw) ?? .api
    }

    private var activeProfile: AIChatProviderProfile? {
        if let activeProfileID, let match = profiles.first(where: { $0.id == activeProfileID }) {
            return match
        }
        return profiles.first
    }

    private var activeConfig: AIChatConfiguration {
        activeProfile?.configuration ?? AIChatConfiguration()
    }

    private var activeHasKey: Bool {
        guard let profile = activeProfile else { return false }
        return AIChatCredentials().key(for: profile) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            modeSelector
            if currentMode == .api {
                activeProfileBar
                transcript
                if let status = session.status {
                    HStack(spacing: 6) {
                        if session.isSending {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "info.circle").font(.caption)
                        }
                        Text(status).font(.caption).lineLimit(3)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                composer
            } else if let targetURL = currentMode.serviceURL {
                AIWebAssistantView(targetURL: targetURL, serviceName: currentMode.title)
            }
        }
        .pageBackground()
        .navigationTitle(currentMode == .api ? "AI 助手" : currentMode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if currentMode == .api {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showClear = true } label: { Image(systemName: "trash") }.accessibilityLabel("清空本次会话")
                    Button { showConfiguration = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("AI 接口配置")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { composing = false } }
            }
        }
        .onAppear {
            loadProfilesIfNeeded()
            if let recapSeed, !didApplyRecapSeed {
                didApplyRecapSeed = true
                selectedModeRaw = AIAssistantMode.api.rawValue
                input = AIChatRecapSeed.buildPrompt(
                    bookTitle: recapSeed.bookTitle,
                    author: recapSeed.author,
                    currentChapterIndex: recapSeed.currentChapterIndex,
                    currentChapterTitle: recapSeed.currentChapterTitle
                )
                addText(name: "\(recapSeed.bookTitle)-前情已读原文.txt", text: recapSeed.readChaptersSummary)
            }
        }
        .onDisappear { session.stop(); cancelAttachmentLoad() }
        .confirmationDialog("清空本次会话和附件？不会删除接口配置。", isPresented: $showClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { cancelAttachmentLoad(); session.clear(); attachments = []; input = "" }
        }
        .sheet(isPresented: $showConfiguration) {
            AIChatConfigurationView(
                profiles: $profiles,
                activeProfileID: $activeProfileID,
                onPersist: persistProfiles
            )
        }
        .sheet(isPresented: $showLibrary) {
            AIChatLibraryAttachmentView { name, json in addText(name: name, text: json) }.environmentObject(appState)
        }
        .sheet(item: $editing) { attachment in
            AIChatAttachmentPreview(attachment: attachment, editable: true) { value in
                if let index = attachments.firstIndex(where: { $0.id == value.id }) { attachments[index] = value }
            }
        }
        .sheet(item: $pending) { submission in
            AIChatSendReview(submission: submission) {
                pending = nil; input = ""; attachments = []; session.send(submission)
            }
        }
        .sheet(item: $generatedSource) { message in
            AIGeneratedSourceReviewView(text: message.text).environmentObject(appState)
        }
        .sheet(item: $fullText) { message in
            NavigationStack {
                AIChatPagedText(text: message.text).navigationTitle("完整回复").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { fullText = nil } } }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.json, .plainText, .text, .image], allowsMultipleSelection: true, onCompletion: importFiles)
    }

    private func loadProfilesIfNeeded() {
        var decoded = (try? JSONDecoder().decode([AIChatProviderProfile].self, from: storedProfiles)) ?? []
        if decoded.isEmpty,
           let legacy = try? JSONDecoder().decode(AIChatConfiguration.self, from: storedConfiguration),
           !legacy.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let migrated = AIChatProviderProfile(
                name: legacy.validatedURL?.host ?? "默认配置",
                endpoint: legacy.endpoint,
                model: legacy.model,
                supportsImages: legacy.supportsImages,
                availableModels: legacy.model.isEmpty ? [] : [legacy.model]
            )
            decoded = [migrated]
            if let existingKey = AIChatCredentials().key(for: legacy) {
                try? AIChatCredentials().save(existingKey, for: migrated)
            }
        }
        profiles = decoded
        if let savedID = UUID(uuidString: activeProfileIDRaw),
           decoded.contains(where: { $0.id == savedID }) {
            activeProfileID = savedID
        } else {
            activeProfileID = decoded.first?.id
        }
        persistProfiles()
    }

    private func persistProfiles() {
        if let activeID = activeProfileID, !profiles.contains(where: { $0.id == activeID }) {
            activeProfileID = profiles.first?.id
        } else if activeProfileID == nil {
            activeProfileID = profiles.first?.id
        }
        storedProfiles = (try? JSONEncoder().encode(profiles)) ?? Data()
        activeProfileIDRaw = activeProfileID?.uuidString ?? ""
        if let current = activeProfile?.configuration {
            storedConfiguration = (try? JSONEncoder().encode(current)) ?? Data()
        } else {
            storedConfiguration = Data()
        }
    }

    private var activeProfileBar: some View {
        HStack(spacing: 8) {
            if let active = activeProfile {
                Menu {
                    Section("切换已保存的 AI 配置") {
                        ForEach(profiles) { profile in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                activeProfileID = profile.id
                                persistProfiles()
                            } label: {
                                HStack {
                                    Text(profile.displayName)
                                    if profile.id == active.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        showConfiguration = true
                    } label: {
                        Label("管理或新增配置…", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(activeHasKey ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(active.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(AppTheme.elevatedCard, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.7))
                }
                .foregroundStyle(.primary)

                let models = Array(Set(active.availableModels + (active.model.isEmpty ? [] : [active.model]))).sorted()
                Menu {
                    if !models.isEmpty {
                        Section("切换模型") {
                            ForEach(models, id: \.self) { modelID in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if let idx = profiles.firstIndex(where: { $0.id == active.id }) {
                                        profiles[idx].model = modelID
                                        persistProfiles()
                                    }
                                } label: {
                                    HStack {
                                        Text(modelID)
                                        if modelID == active.model {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        showConfiguration = true
                    } label: {
                        Label("拉取或编辑模型…", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text(active.model.isEmpty ? "选择模型" : active.model)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(AppTheme.accent.opacity(0.10), in: Capsule())
                }
                .foregroundStyle(.primary)

                Spacer(minLength: 0)
            } else {
                Button {
                    showConfiguration = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text("尚未配置 AI 接口，点此添加配置与拉取模型")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.accent.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var modeSelector: some View {
        Picker("AI 模式", selection: $selectedModeRaw) {
            ForEach(AIAssistantMode.allCases) { mode in
                Text(mode.title).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if session.messages.isEmpty {
                        welcomeCard
                    }
                    ForEach(session.messages) { message in messageRow(message).id(message.id) }
                }.padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("纸间 AI 阅读与书源助手")
                        .font(.headline)
                    if let active = activeProfile {
                        Text("当前：\(active.displayName) · \(active.model.isEmpty ? "未选模型" : active.model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("支持 OpenAI / DeepSeek / 硅基流动等任意兼容接口")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if activeProfile == nil || !activeHasKey {
                Button {
                    showConfiguration = true
                } label: {
                    Label(activeProfile == nil ? "添加 AI 接口配置" : "补充当前配置 API Key", systemImage: "key.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            } else {
                let quickPrompts = [
                    "帮我写一条去除“求月票/作者有话说”的净化正则",
                    "请解释一下 Legado 书源里的 ruleContent 写法",
                    "我附上了一个书源 JSON，请帮我检查哪里解析失败"
                ]
                VStack(alignment: .leading, spacing: 6) {
                    Text("快捷提问")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(quickPrompts, id: \.self) { prompt in
                        Button {
                            input = prompt
                            composing = true
                        } label: {
                            HStack {
                                Text(prompt)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func messageRow(_ message: AIChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(message.role == .user ? "你" : "AI · \(message.modelName ?? "回复")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.role == .user ? AppTheme.accent : .secondary)
                Spacer()
            }
            if !message.text.isEmpty {
                Text(String(message.text.prefix(8000))).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if !message.text.dropFirst(8000).isEmpty {
                    Button("长内容分段查看（复制可获得全文）") { fullText = message }.font(.caption)
                }
            }
            ForEach(message.attachments) { attachment in
                Label(attachment.name, systemImage: attachment.isImage ? "photo" : "doc.text").font(.caption).foregroundStyle(.secondary)
            }
            if message.role == .assistant {
                HStack {
                    Button("复制") { UIPasteboard.general.string = message.text }
                    Button("书源 JSON 复核与测试") { generatedSource = message }
                }.font(.caption).buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(message.role == .user ? AppTheme.accent.opacity(0.09) : AppTheme.elevatedCard,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(attachments) { attachment in
                            HStack(spacing: 8) {
                                Button { editing = attachment } label: { Label(attachment.name, systemImage: attachment.isImage ? "photo" : "doc.text").lineLimit(1) }
                                Button { attachments.removeAll { $0.id == attachment.id } } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("移除 \(attachment.name)")
                            }.font(.caption).padding(8).background(AppTheme.accent.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("UTF-8 文本 / JSON / 图片（每个最多 2 MB）") { showFiles = true }
                    Button("从书源或净化规则选择") { showLibrary = true }
                } label: {
                    Image(systemName: "paperclip.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.accent.opacity(0.88))
                }
                .disabled(attachments.count >= 6 || preparingAttachment || session.isSending)

                TextField("输入消息，可附书源或规则…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composing)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if preparingAttachment {
                    ProgressView().frame(width: 34, height: 34)
                } else if session.isSending {
                    Button {
                        session.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("停止")
                } else {
                    let canSend = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
                    Button {
                        prepareSend()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(canSend ? AppTheme.accent : Color.secondary.opacity(0.35))
                    }
                    .disabled(!canSend)
                    .accessibilityLabel(attachments.isEmpty ? "发送" : "预览并发送")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.background)
    }

    private func prepareSend() {
        guard let profile = activeProfile else {
            session.status = "请先点击上方按钮添加并启用一个 AI 接口配置。"
            showConfiguration = true
            return
        }
        let creds = AIChatCredentials()
        let keyOverride = creds.key(for: profile)
        do {
            let submission = try session.prepare(
                text: input,
                attachments: attachments,
                config: profile.configuration,
                credentials: creds,
                keyOverride: keyOverride
            )
            composing = false
            if attachments.isEmpty {
                input = ""
                session.send(submission)
            } else {
                pending = submission
            }
        } catch {
            session.status = error.localizedDescription
        }
    }

    private func addText(name: String, text: String) {
        guard attachments.count < 6 else { session.status = "每次最多 6 个附件。"; return }
        guard text.utf8.count <= 2_000_000 else { session.status = AIChatFailure.tooLarge.localizedDescription; return }
        preparingAttachment = true
        let revision = UUID(); attachmentRevision = revision
        attachmentTask = Task {
            let clean = await Task.detached(priority: .userInitiated) { AIChatAttachmentPrivacy.scrubJSON(text) }.value
            guard !Task.isCancelled, revision == attachmentRevision else { return }
            attachments.append(.init(name: name, payload: .text(clean))); preparingAttachment = false
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        guard attachments.count + urls.count <= 6 else { session.status = "每次最多 6 个附件。"; return }
        preparingAttachment = true
        let revision = UUID(); attachmentRevision = revision
        attachmentTask = Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try urls.map(AIChatAttachmentLoader.load) } }.value
            guard !Task.isCancelled, revision == attachmentRevision else { return }
            switch result {
            case .success(let values): attachments.append(contentsOf: values)
            case .failure: session.status = AIChatFailure.invalidAttachment.localizedDescription
            }
            preparingAttachment = false
        }
    }

    private func cancelAttachmentLoad() {
        attachmentRevision = UUID(); attachmentTask?.cancel(); attachmentTask = nil; preparingAttachment = false
    }
}

private extension AIChatAttachment {
    var isImage: Bool { if case .jpeg = payload { return true }; return false }
}

private struct AIChatConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var profiles: [AIChatProviderProfile]
    @Binding var activeProfileID: UUID?
    let onPersist: () -> Void

    @State private var editingProfile: AIChatProviderProfile?
    @State private var isCreatingNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有保存任何 AI 配置")
                                .font(.subheadline.weight(.semibold))
                            Text("点击下方「新增 AI 配置」，填入接口地址与 API Key 后即可一键获取模型列表并保存。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(profiles) { profile in
                            let isActive = (activeProfileID ?? profiles.first?.id) == profile.id
                            let hasKey = AIChatCredentials().key(for: profile) != nil
                            HStack(spacing: 12) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    activeProfileID = profile.id
                                    onPersist()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(isActive ? AppTheme.accent : Color.secondary.opacity(0.5))
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(profile.displayName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                if isActive {
                                                    Text("当前使用")
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundStyle(.white)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(AppTheme.accent, in: Capsule())
                                                }
                                            }
                                            Text(profile.model.isEmpty ? "未选择模型" : profile.model)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(AppTheme.accent)
                                                .lineLimit(1)
                                            HStack(spacing: 6) {
                                                Text(profile.configuration.validatedURL?.host ?? profile.endpoint)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                Text(hasKey ? "· 已存 Key" : "· 缺少 Key")
                                                    .font(.caption2.weight(.medium))
                                                    .foregroundStyle(hasKey ? .green : .orange)
                                                if !profile.availableModels.isEmpty {
                                                    Text("· \(profile.availableModels.count) 个模型")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        Spacer(minLength: 4)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button("编辑") {
                                    editingProfile = profile
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { offsets in
                            for index in offsets where profiles.indices.contains(index) {
                                try? AIChatCredentials().remove(for: profiles[index])
                            }
                            profiles.remove(atOffsets: offsets)
                            if let activeID = activeProfileID, !profiles.contains(where: { $0.id == activeID }) {
                                activeProfileID = profiles.first?.id
                            }
                            onPersist()
                        }
                    }

                    Button {
                        isCreatingNew = true
                    } label: {
                        Label("新增 AI 接口配置", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                } header: {
                    Text("已保存的配置（点击左侧即可切换启用）")
                } footer: {
                    Text("支持保存多个服务商（如 DeepSeek、OpenAI、硅基流动、中转站等），随时在聊天顶部一键切换配置和模型。密钥仅存于系统钥匙串。")
                }
                .listRowBackground(AppThemeRowSurface())
            }
            .listStyle(.insetGrouped)
            .pageBackground()
            .navigationTitle("AI 接口管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onPersist()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isCreatingNew) {
                AIChatProfileEditorSheet(initial: AIChatProviderProfile(), isNew: true) { saved in
                    profiles.append(saved)
                    activeProfileID = saved.id
                    onPersist()
                }
            }
            .sheet(item: $editingProfile) { target in
                AIChatProfileEditorSheet(initial: target, isNew: false) { saved in
                    if let idx = profiles.firstIndex(where: { $0.id == saved.id }) {
                        profiles[idx] = saved
                    } else {
                        profiles.append(saved)
                    }
                    activeProfileID = saved.id
                    onPersist()
                }
            }
        }
    }
}

private struct AIChatProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile: AIChatProviderProfile
    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var revealKey = false
    @State private var isFetchingModels = false
    @State private var modelSearch = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @FocusState private var focused: Bool

    let isNew: Bool
    let onSave: (AIChatProviderProfile) -> Void

    init(initial: AIChatProviderProfile, isNew: Bool, onSave: @escaping (AIChatProviderProfile) -> Void) {
        _profile = State(initialValue: initial)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var effectiveKey: String {
        let typed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return AIChatCredentials().key(for: profile) ?? ""
    }

    private var filteredModels: [String] {
        let query = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return profile.availableModels }
        return profile.availableModels.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("快捷模板（点选自动填地址）") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AIChatProviderPreset.all) { preset in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || AIChatProviderPreset.all.contains(where: { $0.name == profile.name }) {
                                        profile.name = preset.name
                                    }
                                    profile.endpoint = preset.endpoint
                                    if profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isNew {
                                        profile.model = preset.defaultModel
                                    }
                                    if profile.availableModels.isEmpty {
                                        profile.availableModels = preset.suggestedModels
                                    }
                                    profile.supportsImages = preset.supportsImages
                                    statusMessage = "已填入 \(preset.name) 模板，粘贴 API Key 后可点「获取模型列表」。"
                                    statusIsError = false
                                } label: {
                                    Text(preset.name)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                                        .foregroundStyle(AppTheme.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(AppThemeRowSurface())

                Section {
                    TextField("配置名称（如 DeepSeek、我的中转站）", text: $profile.name)
                        .focused($focused)
                    TextField("接口地址（如 https://api.deepseek.com 或 /v1）", text: $profile.endpoint, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focused)

                    if let resolved = profile.configuration.resolvedChatURL {
                        Label("实际请求：\(resolved.absoluteString)", systemImage: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else if !profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("地址格式无效，请以 https:// 开头（本机网关允许 http://127.0.0.1）", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("接口信息（自动兼容基础域名或完整路径）")
                }
                .listRowBackground(AppThemeRowSurface())

                Section {
                    HStack(spacing: 8) {
                        if revealKey {
                            TextField(hasStoredKey ? "已保存密钥，留空保留；输入可替换" : "粘贴 API Key（sk-...）", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focused)
                        } else {
                            SecureField(hasStoredKey ? "已保存密钥，留空保留；输入可替换" : "粘贴 API Key（sk-...）", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focused)
                        }
                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("API Key（安全保存在系统钥匙串）")
                }
                .listRowBackground(AppThemeRowSurface())

                Section {
                    HStack {
                        TextField("手动输入或下方点击选择模型 ID", text: $profile.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                    }

                    Button {
                        fetchRemoteModels()
                    } label: {
                        HStack {
                            if isFetchingModels {
                                ProgressView().controlSize(.small)
                                Text("正在从 /models 拉取模型列表…")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("获取模型列表")
                            }
                            Spacer()
                            if !profile.availableModels.isEmpty {
                                Text("共 \(profile.availableModels.count) 个")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    }
                    .disabled(isFetchingModels)

                    if !profile.availableModels.isEmpty {
                        if profile.availableModels.count > 6 {
                            TextField("筛选模型名（如 deepseek / gpt / claude）", text: $modelSearch)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        ForEach(filteredModels.prefix(40), id: \.self) { modelID in
                            let selected = profile.model == modelID
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                profile.model = modelID
                            } label: {
                                HStack {
                                    Text(modelID)
                                        .font(.caption.weight(selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? AppTheme.accent : .primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if filteredModels.count > 40 {
                            Text("还有 \(filteredModels.count - 40) 个模型，可输入关键词筛选")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("此模型支持图片输入（多模态）", isOn: $profile.supportsImages)
                } header: {
                    Text("模型选择")
                }
                .listRowBackground(AppThemeRowSurface())

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(statusIsError ? .red : .secondary)
                    }
                    .listRowBackground(AppThemeRowSurface())
                }
            }
            .navigationTitle(isNew ? "新增 AI 配置" : "编辑 AI 配置")
            .navigationBarTitleDisplayMode(.inline)
            .pageBackground()
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                hasStoredKey = AIChatCredentials().key(for: profile) != nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并启用") { saveProfile() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focused = false }
                }
            }
        }
    }

    private func fetchRemoteModels() {
        focused = false
        guard profile.configuration.resolvedModelsURL != nil else {
            statusMessage = "请先填写有效的 HTTPS 接口地址（例如 https://api.deepseek.com/v1）。"
            statusIsError = true
            return
        }
        let key = effectiveKey
        guard !key.isEmpty else {
            statusMessage = "请先粘贴 API Key，再点击获取模型列表。"
            statusIsError = true
            return
        }
        isFetchingModels = true
        statusMessage = nil
        statusIsError = false
        let configSnapshot = profile.configuration
        Task {
            do {
                let fetched = try await AIChatClient().fetchModels(config: configSnapshot, key: key)
                await MainActor.run {
                    profile.availableModels = fetched
                    if profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let first = fetched.first {
                        profile.model = first
                    }
                    statusMessage = "成功获取 \(fetched.count) 个可用模型，点选后点击右上角「保存并启用」。"
                    statusIsError = false
                    isFetchingModels = false
                    HapticFeedback.success()
                }
            } catch {
                await MainActor.run {
                    statusMessage = "获取模型失败：\(error.localizedDescription)（部分中转站未开放 /models 接口，可直接手动填写模型 ID 后保存）"
                    statusIsError = true
                    isFetchingModels = false
                }
            }
        }
    }

    private func saveProfile() {
        focused = false
        profile.endpoint = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if profile.model.isEmpty, let first = profile.availableModels.first {
            profile.model = first
        }
        guard let validated = profile.configuration.validatedURL else {
            statusMessage = AIChatFailure.configuration.localizedDescription
            statusIsError = true
            return
        }
        guard !profile.model.isEmpty else {
            statusMessage = "请先填写或选择一个模型 ID（可点「获取模型列表」自动拉取）。"
            statusIsError = true
            return
        }
        let keyToSave = effectiveKey
        guard !keyToSave.isEmpty else {
            statusMessage = "请粘贴 API Key 后再保存。"
            statusIsError = true
            return
        }
        profile.endpoint = validated.absoluteString
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.name = validated.host ?? "自定义接口"
        }
        if !profile.availableModels.contains(profile.model) {
            profile.availableModels.insert(profile.model, at: 0)
        }
        do {
            try AIChatCredentials().save(keyToSave, for: profile)
            HapticFeedback.success()
            onSave(profile)
            dismiss()
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }
}

private struct AIChatLibraryAttachmentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let onSelect: (String, String) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("仅选中的资料会加入附件，尚未发送。已知 JSON 凭据字段会移除，但请仍预览脚本、URL 和正文是否含个人信息。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("添加当前净化规则（\(appState.purifyRuleStore.rules.count) 条）") {
                        attach("净化规则.json", appState.purifyRuleStore.rules)
                    }
                }
                .listRowBackground(AppThemeRowSurface())
                Section("选择一个书源") {
                    ForEach(appState.sourceStore.sources.filter { search.isEmpty || $0.bookSourceName.localizedCaseInsensitiveContains(search) }) { source in
                        Button { attach(source.bookSourceName + ".json", source) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.bookSourceName).foregroundStyle(.primary)
                                Text(source.bookSourceUrl).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listRowBackground(AppThemeRowSurface())
            }.searchable(text: $search, prompt: "搜索书源名称")
                .navigationTitle("选取本地资料").navigationBarTitleDisplayMode(.inline)
                .pageBackground()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
    private func attach<T: Encodable>(_ name: String, _ value: T) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return }
        onSelect(name, String(decoding: data, as: UTF8.self)); dismiss()
    }
}

private struct AIChatAttachmentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: AIChatAttachment
    let editable: Bool
    let onSave: (AIChatAttachment) -> Void
    @State private var text = ""
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("请移除个人信息、站点凭据或不想上传的内容。自动处理仅覆盖已知 JSON 字段，不能保证脚本和普通文本不含隐私。")
                    .font(.caption).foregroundStyle(.secondary)
                switch attachment.payload {
                case .text(let value):
                    if editable { TextEditor(text: $text).font(.system(.footnote, design: .monospaced)) }
                    else { ScrollView { Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
                case .jpeg(let data):
                    if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                }
                Text("\(attachment.byteCount) 字节").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
                .navigationTitle(attachment.name).navigationBarTitleDisplayMode(.inline)
                .onAppear { if case .text(let value) = attachment.payload { text = value } }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    if editable, case .text = attachment.payload {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") { var value = attachment; value.payload = .text(text); onSave(value); dismiss() }
                                .disabled(text.utf8.count > 2_000_000)
                        }
                    }
                }
        }
    }
}

private struct AIChatSendReview: View {
    @Environment(\.dismiss) private var dismiss
    let submission: AIChatSubmission
    let onSend: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section("即将发送到") {
                    Text(submission.config.endpoint).font(.footnote).textSelection(.enabled)
                    if submission.config.isLocalHTTPGateway {
                        Text("本次发送到当前设备的本机 HTTP 网关；网关仍可能转发给上游服务商。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("模型：\(submission.config.model)")
                    Text("共 \(submission.history.count) 条消息 · \(submission.history.reduce(0) { $0 + $1.attachments.count }) 个附件 · \(submission.byteCount) 字节")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("包含以下全部历史和附件，而不只是最新输入。发送即会上传到所配置服务商，可能产生费用。取消不会发起请求。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(AppThemeRowSurface())
                ForEach(submission.history) { message in
                    Section(message.role == .user ? "你的消息" : "AI 历史回复") {
                        Text(String(message.text.prefix(8000))).textSelection(.enabled)
                        if !message.text.dropFirst(8000).isEmpty {
                            NavigationLink("分段查看完整消息") { AIChatPagedText(text: message.text) }
                        }
                        ForEach(message.attachments) { attachment in
                            NavigationLink(attachment.name) { AIChatInlineAttachment(attachment: attachment) }
                        }
                    }
                    .listRowBackground(AppThemeRowSurface())
                }
            }.pageBackground().navigationTitle("发送前确认").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("确认上传并发送", action: onSend) }
                }
        }
    }
}

private struct AIChatInlineAttachment: View {
    let attachment: AIChatAttachment
    var body: some View {
        Group {
            switch attachment.payload {
            case .text(let text): AIChatPagedText(text: text)
            case .jpeg(let data): ScrollView { if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().padding(16) } }
            }
        }.navigationTitle(attachment.name).navigationBarTitleDisplayMode(.inline)
    }
}

/// Do not ask SwiftUI to lay out an entire multi-megabyte source attachment.
private struct AIChatPagedText: View {
    let text: String
    @State private var start: String.Index?
    @State private var previous: [String.Index] = []
    var body: some View {
        let lower = start ?? text.startIndex
        let upper = text.index(lower, offsetBy: 6000, limitedBy: text.endIndex) ?? text.endIndex
        return VStack(spacing: 8) {
            ScrollView {
                Text(String(text[lower..<upper])).font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.id(previous.count)
            HStack {
                Button("上一段") { if let value = previous.popLast() { start = value } }.disabled(previous.isEmpty)
                Spacer()
                Text("第 \(previous.count + 1) 段").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("下一段") {
                    let current = start ?? text.startIndex
                    let next = text.index(current, offsetBy: 6000, limitedBy: text.endIndex) ?? text.endIndex
                    if current < next { previous.append(current); start = next }
                }.disabled(upper == text.endIndex)
            }.padding(.horizontal, 16)
            Button("复制全文") { UIPasteboard.general.string = text }.font(.caption).padding(.bottom, 12)
        }
    }
}

// MARK: - AI Assistant Multi-Mode & Web AI Integration

enum AIAssistantMode: String, CaseIterable, Identifiable {
    case api = "api"
    case doubao = "doubao"
    case kimi = "kimi"
    case deepseek = "deepseek"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .api: return "接口"
        case .doubao: return "豆包"
        case .kimi: return "Kimi"
        case .deepseek: return "DeepSeek"
        }
    }

    var serviceURL: URL? {
        switch self {
        case .api: return nil
        case .doubao: return URL(string: "https://www.doubao.com/chat/")
        case .kimi: return URL(string: "https://kimi.moonshot.cn/")
        case .deepseek: return URL(string: "https://chat.deepseek.com/")
        }
    }
}

struct AIWebAssistantView: View {
    let targetURL: URL
    let serviceName: String
    @Environment(\.openURL) private var openURL
    @StateObject private var webState = AIWebState()

    var body: some View {
        VStack(spacing: 0) {
            if webState.isLoading && webState.progress < 1.0 {
                ProgressView(value: webState.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(height: 2)
            }
            AIWebViewContainer(targetURL: targetURL, state: webState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            webToolbar
        }
    }

    private var webToolbar: some View {
        HStack(spacing: 18) {
            Button {
                webState.webView?.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!webState.canGoBack)

            Button {
                webState.webView?.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!webState.canGoForward)

            Button {
                webState.webView?.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            Button {
                webState.webView?.load(URLRequest(url: targetURL))
            } label: {
                Image(systemName: "house")
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(webState.currentHost.isEmpty ? serviceName : webState.currentHost)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                if let url = webState.currentURL ?? Optional(targetURL) {
                    openURL(url)
                }
            } label: {
                Image(systemName: "safari")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

@MainActor
final class AIWebState: ObservableObject {
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentURL: URL?
    @Published var currentHost: String = ""
    weak var webView: WKWebView?
}

struct AIWebViewContainer: UIViewRepresentable {
    let targetURL: URL
    @ObservedObject var state: AIWebState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.setupObservation(for: webView)
        state.webView = webView
        let request = URLRequest(url: targetURL)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        state.webView = uiView
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let state: AIWebState
        private var progressObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?

        init(state: AIWebState) {
            self.state = state
        }

        func setupObservation(for webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.state.progress = view.estimatedProgress
                }
            }
            canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.state.canGoBack = view.canGoBack
                }
            }
            canGoForwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.state.canGoForward = view.canGoForward
                }
            }
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.state.currentURL = view.url
                    self?.state.currentHost = view.url?.host ?? ""
                }
            }
        }

        func cleanup() {
            progressObservation?.invalidate()
            canGoBackObservation?.invalidate()
            canGoForwardObservation?.invalidate()
            urlObservation?.invalidate()
            progressObservation = nil
            canGoBackObservation = nil
            canGoForwardObservation = nil
            urlObservation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = false
                state.canGoBack = webView.canGoBack
                state.canGoForward = webView.canGoForward
                state.currentURL = webView.url
                state.currentHost = webView.url?.host ?? ""
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                state.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                state.isLoading = false
            }
        }
    }
}
