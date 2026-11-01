import SwiftUI
import UniformTypeIdentifiers

struct AIChatView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("settings.ai.configuration") private var storedConfiguration = Data()
    @StateObject private var session = AIChatSession()
    @State private var config = AIChatConfiguration()
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
    @State private var showClear = false
    @FocusState private var composing: Bool

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if let status = session.status {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 6)
            }
            composer
        }
        .pageBackground()
        .navigationTitle("AI 助手")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showClear = true } label: { Image(systemName: "trash") }.accessibilityLabel("清空本次会话")
                Button { showConfiguration = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("AI 接口配置")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { composing = false } }
        }
        .onAppear { if let saved = try? JSONDecoder().decode(AIChatConfiguration.self, from: storedConfiguration) { config = saved } }
        .onDisappear { session.stop(); cancelAttachmentLoad() }
        .confirmationDialog("清空本次会话和附件？不会删除接口配置。", isPresented: $showClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { cancelAttachmentLoad(); session.clear(); attachments = []; input = "" }
        }
        .sheet(isPresented: $showConfiguration) {
            AIChatConfigurationView(initial: config) { value in
                config = value; storedConfiguration = (try? JSONEncoder().encode(value)) ?? Data()
            }
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
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.json, .plainText, .text, .image], allowsMultipleSelection: true, onCompletion: importFiles)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if session.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("由你选择接口与发送内容", systemImage: "bubble.left.and.bubble.right").font(.headline)
                            Text("可聊天、解释规则，或带上书源让 AI 修改。仅支持 Chat Completions 兼容接口，图片需模型支持。会话只在本页内存保留，不写入诊断和备份。")
                            Text("附件是待分析资料，不是应用指令。AI 可能编造规则；返回内容不会自动执行或覆盖书源。")
                            Button("配置接口和模型") { showConfiguration = true }.buttonStyle(.bordered)
                        }.font(.subheadline).foregroundStyle(.secondary).padding(16)
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

    private func messageRow(_ message: AIChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.role == .user ? "你" : "AI · \(message.modelName ?? "回复")").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if !message.text.isEmpty { Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
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
        .padding(14).background(message.role == .user ? AppTheme.accent.opacity(0.09) : AppTheme.elevatedCard,
                                 in: RoundedRectangle(cornerRadius: 16))
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
            TextField("输入消息，可附书源或规则…", text: $input, axis: .vertical)
                .lineLimit(2...5).focused($composing).padding(10).background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Menu {
                    Button("UTF-8 文本 / JSON / 图片（每个最多 2 MB）") { showFiles = true }
                    Button("从书源或净化规则选择") { showLibrary = true }
                } label: { Label("附件", systemImage: "paperclip") }
                .disabled(attachments.count >= 6 || preparingAttachment || session.isSending)
                Spacer()
                if preparingAttachment { ProgressView() }
                if session.isSending {
                    Button("停止") { session.stop() }.buttonStyle(.bordered)
                } else {
                    Button("预览并发送") { prepareSend() }.buttonStyle(.borderedProminent)
                        .disabled(preparingAttachment || (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty))
                }
            }.font(.subheadline)
        }.padding(12).background(AppTheme.background)
    }

    private func prepareSend() {
        do { pending = try session.prepare(text: input, attachments: attachments, config: config, credentials: AIChatCredentials()); composing = false }
        catch { session.status = error.localizedDescription }
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
    @State private var config: AIChatConfiguration
    @State private var key = ""
    @State private var savedKey = false
    @State private var status: String?
    @FocusState private var focused: Bool
    let onSave: (AIChatConfiguration) -> Void
    init(initial: AIChatConfiguration, onSave: @escaping (AIChatConfiguration) -> Void) {
        _config = State(initialValue: initial); self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Chat Completions 兼容接口") {
                    TextField("完整 HTTPS 地址，以 /chat/completions 等路径结尾", text: $config.endpoint, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).focused($focused)
                    TextField("服务商提供的模型 ID", text: $config.model).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                    Toggle("此模型支持图片", isOn: $config.supportsImages)
                    Text("填写完整接口地址，不会替你拼接路径或更换模型。不支持 Responses、Claude 原生等不同协议的接口。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("API Key · 仅钥匙串") {
                    SecureField(savedKey ? "已有密钥，留空保留；填入可替换" : "粘贴 API Key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                    if savedKey {
                        Button("删除当前接口密钥", role: .destructive) {
                            do { try AIChatCredentials().remove(for: config); savedKey = false; key = "" }
                            catch { status = error.localizedDescription }
                        }
                    }
                    Text("密钥绑定到完整接口地址，改地址不会沿用旧密钥。不会写入 UserDefaults、聊天内容或日志。第三方接口可能留存会话并按用量收费。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let status { Section { Text(status).font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle("AI 配置").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .onAppear { savedKey = AIChatCredentials().key(for: config) != nil }
            .onChange(of: config.endpoint) { _ in key = ""; savedKey = AIChatCredentials().key(for: config) != nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focused = false } }
            }
        }
    }
    private func save() {
        guard config.validatedURL != nil, !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = AIChatFailure.configuration.localizedDescription; return }
        do {
            if !key.isEmpty { try AIChatCredentials().save(key, for: config) }
            config.endpoint = config.validatedURL!.absoluteString
            config.model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
            onSave(config); key = ""; dismiss()
        } catch { status = error.localizedDescription }
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
            }.searchable(text: $search, prompt: "搜索书源名称")
                .navigationTitle("选取本地资料").navigationBarTitleDisplayMode(.inline)
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
                    Text("模型：\(submission.config.model)")
                    Text("共 \(submission.history.count) 条消息 · \(submission.history.reduce(0) { $0 + $1.attachments.count }) 个附件 · \(submission.byteCount) 字节")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("包含以下全部历史和附件，而不只是最新输入。发送即会上传到所配置服务商，可能产生费用。取消不会发起请求。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(submission.history) { message in
                    Section(message.role == .user ? "你的消息" : "AI 历史回复") {
                        Text(message.text).textSelection(.enabled)
                        ForEach(message.attachments) { attachment in
                            NavigationLink(attachment.name) { AIChatInlineAttachment(attachment: attachment) }
                        }
                    }
                }
            }.navigationTitle("发送前确认").navigationBarTitleDisplayMode(.inline)
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
        ScrollView {
            switch attachment.payload {
            case .text(let text): Text(text).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding(16)
            case .jpeg(let data): if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().padding(16) }
            }
        }.navigationTitle(attachment.name).navigationBarTitleDisplayMode(.inline)
    }
}
