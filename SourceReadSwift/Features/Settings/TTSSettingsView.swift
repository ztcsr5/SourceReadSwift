import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Cloud TTS configuration. Credentials are stored in the Keychain through
/// `CloudTTSCredentialsStore`; only the selected engine lives in UserDefaults.
struct TTSSettingsView: View {
    private enum LocalVoiceFilter: String, CaseIterable, Identifiable {
        case chinese = "中文"
        case highQuality = "高质量"
        case all = "全部"
        var id: String { rawValue }
    }

    @AppStorage("reader.ttsEngine") private var engineRawValue: String = TTSEngineKind.local.rawValue
    @AppStorage("reader.httpTTSVoiceID") private var httpVoiceID: Int = HttpTTSVoice.defaultVoiceID
    @AppStorage("reader.localVoiceIdentifier") private var localVoiceIdentifier = ""

    @State private var appId = ""
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var voiceName = "xiaoyan"
    @State private var speed: Double = 50
    @State private var volume: Double = 50
    @State private var pitch: Double = 50

    @State private var statusMessage: String?
    @State private var isTesting = false
    @State private var isTestingHTTP = false
    @State private var previewPlayer: CloudTTSPlayer?
    @State private var previewSynthesizer: AVSpeechSynthesizer?
    @State private var previewTask: Task<Void, Never>?
    @State private var previewID = UUID()
    @State private var showVoiceImporter = false
    @State private var importedVoiceNames: [String] = []
    @State private var voiceStatusMessage: String?
    @State private var isUpdatingVoices = false
    @State private var showVoiceRemovalConfirmation = false
    @State private var azureRegion = "eastasia"
    @State private var azureKey = ""
    @State private var availableLocalVoices: [AVSpeechSynthesisVoice] = []
    @State private var localVoiceFilter: LocalVoiceFilter = .chinese
    @State private var localVoiceSearch = ""
    @State private var httpVoices: [HttpTTSVoice] = HttpTTSVoiceStore.allVoices()
    @State private var customHttpVoiceCount: Int = HttpTTSVoiceStore.loadCustomVoices().count
    @State private var showHttpVoiceManager = false

    private let credentialStore = CloudTTSCredentialsStore()
    private let client = CloudTTSClient()
    private let httpClient = HttpTTSClient()

    private var engine: TTSEngineKind {
        TTSEngineKind(rawValue: engineRawValue) ?? .local
    }

    var body: some View {
        Form {
            Section {
                Picker("朗读引擎", selection: Binding(
                    get: { TTSEngineKind(rawValue: engineRawValue) ?? .local },
                    set: { engineRawValue = $0.rawValue }
                )) {
                    ForEach(TTSEngineKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                Text(engine.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("引擎")
            }
            .listRowBackground(AppThemeRowSurface())

            if engine == .local {
                Section {
                    Picker("筛选", selection: $localVoiceFilter) {
                        ForEach(LocalVoiceFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("搜索音色名称或语言代码（如 zh-CN）", text: $localVoiceSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        localVoiceIdentifier = ""
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自动跟随系统推荐 (zh-CN)")
                                    .foregroundStyle(.primary)
                                Text("不锁定音色 ID，由系统按语种挑选最稳音色")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if localVoiceIdentifier.isEmpty {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if filteredLocalVoices.isEmpty {
                        Text("当前筛选条件下没有匹配的系统音色，可在系统设置 → 辅助功能 → 朗读内容 → 声音 下载增强音色。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredLocalVoices, id: \.identifier) { voice in
                            HStack(spacing: 10) {
                                Button {
                                    localVoiceIdentifier = voice.identifier
                                } label: {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(voice.name)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                if let qualityLabel = Self.qualityLabel(for: voice.quality) {
                                                    Text(qualityLabel)
                                                        .font(.caption2.weight(.semibold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(AppTheme.accent.opacity(0.14), in: Capsule())
                                                        .foregroundStyle(AppTheme.accent)
                                                }
                                            }
                                            Text(voice.language)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if voice.identifier == localVoiceIdentifier {
                                            Image(systemName: "checkmark")
                                                .fontWeight(.semibold)
                                                .foregroundStyle(AppTheme.accent)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button("试听") {
                                    previewLocalVoice(voice)
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                } header: {
                    Text("系统语音音色筛选")
                } footer: {
                    Text("高质量（增强/Siri 级）离线音色可在 iOS「系统设置 → 辅助功能 → 实时语音/朗读内容 → 声音」下载后立即出现在此处。")
                }
                .listRowBackground(AppThemeRowSurface())
            }

            if engine == .http {
                Section {
                    Picker("发音人", selection: $httpVoiceID) {
                        ForEach(httpVoices) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    Button {
                        showHttpVoiceManager = true
                    } label: {
                        HStack {
                            Label("管理自定义发音人 / 导入 httpTTS.json", systemImage: "slider.horizontal.3")
                            Spacer()
                            if customHttpVoiceCount > 0 {
                                Text("\(customHttpVoiceCount) 条自定义")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        self.testHTTPVoiceSynthesis()
                    } label: {
                        HStack {
                            Label("测试 HTTP 语音", systemImage: "waveform")
                            Spacer()
                            if isTestingHTTP {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting || isTestingHTTP)
                } header: {
                    Text("在线 HTTP 语音")
                } footer: {
                    Text("支持 Legado / 阅读标准 httpTTS.json 模板导入、自建与编辑测试。百度公共预设可能限流；晓萱、晓伊、晓晓、云希使用 Azure 官方服务，需自己的 Speech Key。")
                }
                .listRowBackground(AppThemeRowSurface())
                Section {
                    TextField("资源区域（如 eastasia）", text: $azureRegion)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Azure Speech Key", text: $azureKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("保存 Azure 凭据") {
                        do {
                            try AzureTTSCredentialsStore().save(AzureTTSCredentials(
                                region: azureRegion.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                                key: azureKey.trimmingCharacters(in: .whitespacesAndNewlines)))
                            statusMessage = "Azure 凭据已保存到 Keychain"
                        } catch { statusMessage = error.localizedDescription }
                    }
                    Button("清除 Azure 凭据", role: .destructive) {
                        do {
                            try AzureTTSCredentialsStore().clear()
                            azureKey = ""
                            statusMessage = "Azure 凭据已清除"
                        } catch { statusMessage = error.localizedDescription }
                    }
                } header: { Text("Azure 特色音色") }
                .listRowBackground(AppThemeRowSurface())
            }

            if engine == .file {
                Section {
                    Button {
                        showVoiceImporter = true
                    } label: {
                        Label("导入本地音频", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isUpdatingVoices)

                    if importedVoiceNames.isEmpty {
                        Text("还没有导入音频。文件名用段落序号：0.mp3、1.mp3…（也认 p0.mp3）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(importedVoiceNames.prefix(12), id: \.self) { name in
                            HStack {
                                Text(name)
                                    .font(.footnote)
                                    .lineLimit(1)
                                Spacer()
                                if let index = LocalVoiceLibrary.paragraphIndex(ofFileName: name) {
                                    Text("第 \(index) 段")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if importedVoiceNames.count > 12 {
                            Text("另有 \(importedVoiceNames.count - 12) 个文件")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        showVoiceRemovalConfirmation = true
                    } label: {
                        Label("清空本地音频", systemImage: "trash")
                    }
                    .disabled(importedVoiceNames.isEmpty || isUpdatingVoices)
                } header: {
                    Text("本地声音")
                } footer: {
                    Text("按段落序号一一对应：朗读到第 N 段就播 N.*，缺文件的段落直接跳过，不会联网合成。音频存在 App 沙盒内，不参与 iCloud 备份。")
                }
                .listRowBackground(AppThemeRowSurface())
            }

            Section {
                TextField("App ID", text: $appId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Secret", text: $apiSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("发音人（vcn）", text: $voiceName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("讯飞凭据")
            } footer: {
                Text("凭据保存在系统 Keychain，不写入 UserDefaults，也不会随备份导出。")
            }
            .listRowBackground(AppThemeRowSurface())

            Section("合成参数") {
                sliderRow(title: "语速", value: $speed)
                sliderRow(title: "音量", value: $volume)
                sliderRow(title: "音调", value: $pitch)
            }
            .listRowBackground(AppThemeRowSurface())

            Section {
                Button {
                    self.saveCredentials()
                } label: {
                    Label("保存凭据", systemImage: "key.horizontal")
                }

                Button {
                    self.testSynthesis()
                } label: {
                    HStack {
                        Label("测试合成", systemImage: "waveform")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTesting || isTestingHTTP || !draftCredentials.isConfigured)

                Button(role: .destructive) {
                    self.clearCredentials()
                } label: {
                    Label("清除凭据", systemImage: "trash")
                }
            }
            .listRowBackground(AppThemeRowSurface())

            if let statusMessage {
                Section("状态") {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if isTesting || isTestingHTTP {
                        Button("取消试听") {
                            stopPreview()
                            self.statusMessage = "已取消试听"
                        }
                    }
                    if let voiceStatusMessage {
                        Text(voiceStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(AppThemeRowSurface())
            } else if let voiceStatusMessage {
                Section("状态") {
                    Text(voiceStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(AppThemeRowSurface())
            }
        }
        .pageBackground()
        .navigationTitle("语音朗读")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("清空 \(importedVoiceNames.count) 个本地音频？", isPresented: $showVoiceRemovalConfirmation) {
            Button("清空本地音频", role: .destructive) { clearLocalVoices() }
            Button("取消", role: .cancel) {}
        } message: { Text("清空后，需要重新导入才能使用本地声音朗读。") }
        .fileImporter(
            isPresented: $showVoiceImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importLocalVoices(urls)
            case .failure(let error):
                voiceStatusMessage = "导入失败：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showHttpVoiceManager) {
            HttpTTSVoiceManagerSheet(selectedVoiceID: $httpVoiceID) {
                reloadHttpVoices()
            }
        }
        .onAppear {
            if let credentials = AzureTTSCredentialsStore().load() {
                azureRegion = credentials.region; azureKey = credentials.key
            }
            loadCredentials()
            refreshImportedVoices()
            reloadLocalVoices()
            reloadHttpVoices()
        }
        .onDisappear { stopPreview() }
        .onChange(of: engineRawValue) { _ in
            stopPreview()
            statusMessage = nil
        }
    }

    private func refreshImportedVoices() {
        importedVoiceNames = LocalVoiceLibrary.importedFileNames()
    }

    private func importLocalVoices(_ urls: [URL]) {
        guard !isUpdatingVoices else { return }
        isUpdatingVoices = true
        voiceStatusMessage = "正在导入音频…"
        Task { @MainActor in
            let report = await Task.detached(priority: .userInitiated) {
                LocalVoiceLibrary.importFilesWithReport(urls)
            }.value
            refreshImportedVoices()
            var messages = ["已导入 \(report.importedCount) 个音频，共 \(importedVoiceNames.count) 个"]
            if report.skippedCount > 0 { messages.append("跳过 \(report.skippedCount) 个不支持的文件") }
            if !report.failures.isEmpty {
                messages.append("\(report.failures.count) 个文件导入失败，原有音频已保留")
                messages.append(contentsOf: report.failures.prefix(3))
            }
            voiceStatusMessage = messages.joined(separator: "\n")
            isUpdatingVoices = false
        }
    }

    private func clearLocalVoices() {
        guard !isUpdatingVoices else { return }
        isUpdatingVoices = true
        voiceStatusMessage = "正在清空音频…"
        Task { @MainActor in
            let failures = await Task.detached(priority: .userInitiated) {
                LocalVoiceLibrary.clearReportingFailures()
            }.value
            refreshImportedVoices()
            voiceStatusMessage = failures.isEmpty ? "已清空本地音频"
                : (["部分音频未能删除"] + Array(failures.prefix(3))).joined(separator: "\n")
            isUpdatingVoices = false
        }
    }

    private var draftCredentials: CloudTTSCredentials {
        CloudTTSCredentials(
            appId: appId,
            apiKey: apiKey,
            apiSecret: apiSecret,
            voiceName: voiceName,
            speed: Int(speed.rounded()),
            volume: Int(volume.rounded()),
            pitch: Int(pitch.rounded())
        )
    }

    private func sliderRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...100, step: 1)
        }
    }

    private func loadCredentials() {
        guard let saved = credentialStore.load() else { return }
        appId = saved.appId
        apiKey = saved.apiKey
        apiSecret = saved.apiSecret
        voiceName = saved.voiceName
        speed = Double(saved.speed)
        volume = Double(saved.volume)
        pitch = Double(saved.pitch)
    }

    private func saveCredentials() {
        do {
            try credentialStore.save(draftCredentials)
            statusMessage = "凭据已保存到 Keychain"
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func clearCredentials() {
        do {
            try credentialStore.clear()
            appId = ""
            apiKey = ""
            apiSecret = ""
            statusMessage = "凭据已清除"
        } catch {
            statusMessage = "清除失败：\(error.localizedDescription)"
        }
    }

    private func testSynthesis() {
        let credentials = draftCredentials
        guard credentials.isConfigured else {
            statusMessage = "请先填写 App ID、API Key、API Secret"
            return
        }
        beginPreview(isHTTP: false) {
            try await client.synthesize(text: "纸间阅读，云端语音测试。", credentials: credentials)
        }
    }

    private var selectedHTTPVoice: HttpTTSVoice? {
        HttpTTSVoiceStore.voice(id: httpVoiceID)
    }

    private var filteredLocalVoices: [AVSpeechSynthesisVoice] {
        let query = localVoiceSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return availableLocalVoices.filter { voice in
            let matchesCategory: Bool
            switch localVoiceFilter {
            case .chinese:
                matchesCategory = voice.language.lowercased().hasPrefix("zh")
            case .highQuality:
                matchesCategory = voice.quality != .default
            case .all:
                matchesCategory = true
            }
            guard matchesCategory else { return false }
            guard !query.isEmpty else { return true }
            return voice.name.lowercased().contains(query)
                || voice.language.lowercased().contains(query)
                || voice.identifier.lowercased().contains(query)
        }
    }

    private func reloadLocalVoices() {
        availableLocalVoices = AVSpeechSynthesisVoice.speechVoices().sorted { lhs, rhs in
            let lhsChinese = lhs.language.lowercased().hasPrefix("zh")
            let rhsChinese = rhs.language.lowercased().hasPrefix("zh")
            if lhsChinese != rhsChinese { return lhsChinese }
            if lhs.quality.rawValue != rhs.quality.rawValue {
                return lhs.quality.rawValue > rhs.quality.rawValue
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private func reloadHttpVoices() {
        let all = HttpTTSVoiceStore.allVoices()
        httpVoices = all
        customHttpVoiceCount = HttpTTSVoiceStore.loadCustomVoices().count
        if !all.contains(where: { $0.id == httpVoiceID }), let first = all.first {
            httpVoiceID = first.id
        }
    }

    private static func qualityLabel(for quality: AVSpeechSynthesisVoiceQuality) -> String? {
        switch quality {
        case .enhanced: return "增强"
        case .premium: return "Siri 级"
        default: return nil
        }
    }

    private func previewLocalVoice(_ voice: AVSpeechSynthesisVoice) {
        stopPreview()
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "纸间阅读，这是「\(voice.name)」的朗读音色试听。")
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        previewSynthesizer = synth
        statusMessage = "正在试听系统音色：\(voice.name)（\(voice.language)）"
        synth.speak(utterance)
    }

    private func testHTTPVoiceSynthesis() {
        guard let voice = selectedHTTPVoice else {
            statusMessage = "没有可用的 HTTP 语音预设"
            return
        }
        beginPreview(isHTTP: true) {
            try await httpClient.synthesize(voice: voice, text: "纸间阅读，在线语音测试。", speed: 5)
        }
    }

    private func stopPreview() {
        previewID = UUID()
        previewTask?.cancel()
        previewTask = nil
        previewPlayer?.onFinish = nil
        previewPlayer?.onError = nil
        previewPlayer?.stop()
        previewPlayer = nil
        previewSynthesizer?.stopSpeaking(at: .immediate)
        previewSynthesizer = nil
        isTesting = false
        isTestingHTTP = false
    }

    private func beginPreview(isHTTP: Bool, synthesize: @escaping () async throws -> Data) {
        stopPreview()
        let requestID = UUID()
        previewID = requestID
        let channel = isHTTP ? "HTTP 语音" : "讯飞语音"
        isTesting = !isHTTP
        isTestingHTTP = isHTTP
        statusMessage = "正在请求\(channel)…"
        previewTask = Task { @MainActor in
            do {
                let audio = try await synthesize()
                guard !Task.isCancelled, previewID == requestID else { return }
                try playPreview(audio, channel: channel, requestID: requestID)
                statusMessage = "\(channel)合成成功：\(audio.count) 字节，正在播放"
            } catch {
                guard !Task.isCancelled, previewID == requestID else { return }
                statusMessage = "\(channel)失败：\(error.localizedDescription)"
            }
            isTesting = false
            isTestingHTTP = false
            previewTask = nil
        }
    }

    private func playPreview(_ audio: Data, channel: String, requestID: UUID) throws {
        let player = CloudTTSPlayer()
        player.onFinish = {
            Task { @MainActor in
                guard previewID == requestID else { return }
                statusMessage = "\(channel)播放完成"
            }
        }
        player.onError = { error in
            Task { @MainActor in
                guard previewID == requestID else { return }
                statusMessage = "\(channel)播放失败：\(error.localizedDescription)"
            }
        }
        previewPlayer = player
        try player.play(data: audio)
    }
}

private struct HttpTTSVoiceManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedVoiceID: Int
    let onVoicesChanged: () -> Void

    @State private var customVoices: [HttpTTSVoice] = []
    @State private var editingVoice: HttpTTSVoice?
    @State private var showJSONImporter = false
    @State private var showJSONPasteSheet = false
    @State private var pastedJSON = ""
    @State private var statusMessage: String?
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        let newID = HttpTTSVoiceStore.makeNewVoiceID(existing: customVoices)
                        editingVoice = HttpTTSVoice(
                            id: newID,
                            name: "新建 HTTP 音色",
                            url: #"https://example.com/tts?text={{java.encodeURI(speakText)}}&speed={{speakSpeed}}"#
                        )
                    } label: {
                        Label("新建 HTTP 发音人", systemImage: "plus.circle")
                    }

                    Button {
                        showJSONImporter = true
                    } label: {
                        Label("从文件导入 httpTTS.json", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        pastedJSON = ""
                        showJSONPasteSheet = true
                    } label: {
                        Label("粘贴 httpTTS.json 导入", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        exportCustomJSON()
                    } label: {
                        Label("导出自定义发音人 JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(customVoices.isEmpty)
                } header: {
                    Text("导入与新建")
                }

                Section {
                    if customVoices.isEmpty {
                        Text("还没有自定义 HTTP 发音人，可导入 Legado httpTTS.json 或新建模板。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(customVoices) { voice in
                            HStack(spacing: 10) {
                                Button {
                                    selectedVoiceID = voice.id
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(voice.name)
                                                .foregroundStyle(.primary)
                                            Text(voice.url)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        if voice.id == selectedVoiceID {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(AppTheme.accent)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button("编辑") {
                                    editingVoice = voice
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteCustomVoice(id: voice.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("自定义发音人（\(customVoices.count)）")
                }

                Section("内置预设（\(HttpTTSVoice.defaultVoices.count)）") {
                    ForEach(HttpTTSVoice.defaultVoices) { voice in
                        Button {
                            selectedVoiceID = voice.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(voice.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if voice.id == selectedVoiceID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("HTTP 发音人管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { reload() }
            .fileImporter(
                isPresented: $showJSONImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        let outcome = try HttpTTSVoiceStore.importJSON(data)
                        reload()
                        onVoicesChanged()
                        if let first = outcome.voices.first {
                            selectedVoiceID = first.id
                        }
                        statusMessage = "导入成功：新增 \(outcome.added) 个，当前共 \(outcome.voices.count) 个自定义发音人"
                    } catch {
                        statusMessage = "导入失败：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    statusMessage = "读取文件失败：\(error.localizedDescription)"
                }
            }
            .sheet(item: $editingVoice) { voice in
                HttpTTSVoiceEditorSheet(initialVoice: voice) { saved in
                    do {
                        _ = try HttpTTSVoiceStore.upsert(saved)
                        selectedVoiceID = saved.id
                        reload()
                        onVoicesChanged()
                        statusMessage = "已保存「\(saved.name)」"
                    } catch {
                        statusMessage = "保存失败：\(error.localizedDescription)"
                    }
                }
            }
            .sheet(isPresented: $showJSONPasteSheet) {
                NavigationStack {
                    VStack(spacing: 12) {
                        Text("粘贴 Legado / 阅读 httpTTS.json（支持数组或单条对象）：")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TextEditor(text: $pastedJSON)
                            .font(.system(.caption, design: .monospaced))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )
                    }
                    .padding()
                    .navigationTitle("粘贴导入 httpTTS.json")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showJSONPasteSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") {
                                guard let data = pastedJSON.data(using: .utf8) else { return }
                                do {
                                    let outcome = try HttpTTSVoiceStore.importJSON(data)
                                    reload()
                                    onVoicesChanged()
                                    if let first = outcome.voices.first {
                                        selectedVoiceID = first.id
                                    }
                                    statusMessage = "导入成功：新增 \(outcome.added) 个，当前共 \(outcome.voices.count) 个自定义发音人"
                                    showJSONPasteSheet = false
                                } catch {
                                    statusMessage = "JSON 解析失败：\(error.localizedDescription)"
                                    showJSONPasteSheet = false
                                }
                            }
                            .disabled(pastedJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { exportURL != nil },
                set: { if !$0 { exportURL = nil } }
            )) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
        }
    }

    private func reload() {
        customVoices = HttpTTSVoiceStore.loadCustomVoices()
    }

    private func deleteCustomVoice(id: Int) {
        do {
            _ = try HttpTTSVoiceStore.remove(id: id)
            reload()
            onVoicesChanged()
            if selectedVoiceID == id, let fallback = HttpTTSVoiceStore.allVoices().first {
                selectedVoiceID = fallback.id
            }
            statusMessage = "已删除自定义发音人"
        } catch {
            statusMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    private func exportCustomJSON() {
        do {
            let data = try HttpTTSVoiceStore.exportJSON(customVoices)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("httpTTS_custom.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }
}

private struct HttpTTSVoiceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialVoice: HttpTTSVoice
    let onSave: (HttpTTSVoice) -> Void

    @State private var name: String
    @State private var url: String
    @State private var header: String
    @State private var contentType: String
    @State private var isTesting = false
    @State private var testStatus: String?
    @State private var previewPlayer: CloudTTSPlayer?
    @State private var testTask: Task<Void, Never>?

    init(initialVoice: HttpTTSVoice, onSave: @escaping (HttpTTSVoice) -> Void) {
        self.initialVoice = initialVoice
        self.onSave = onSave
        _name = State(initialValue: initialVoice.name)
        _url = State(initialValue: initialVoice.url)
        _header = State(initialValue: initialVoice.header ?? "")
        _contentType = State(initialValue: initialVoice.contentType ?? "")
    }

    private var draftVoice: HttpTTSVoice {
        HttpTTSVoice(
            id: initialVoice.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            contentType: contentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : contentType.trimmingCharacters(in: .whitespacesAndNewlines),
            loginUrl: initialVoice.loginUrl,
            concurrentRate: initialVoice.concurrentRate,
            header: header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : header.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("发音人名称", text: $name)
                    TextField("音频类型（可选，如 audio/mpeg）", text: $contentType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextEditor(text: $url)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 110)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("URL 模板（支持 {{speakText}} 与 {{speakSpeed}}）")
                }
                Section {
                    TextEditor(text: $header)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 70)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("请求头 JSON（可选）")
                }
                Section {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Label("测试当前模板", systemImage: "waveform")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(isTesting || draftVoice.url.isEmpty)
                    if let testStatus {
                        Text(testStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("编辑 HTTP 发音人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draftVoice)
                        dismiss()
                    }
                    .disabled(draftVoice.name.isEmpty || draftVoice.url.isEmpty)
                }
            }
            .onDisappear {
                testTask?.cancel()
                previewPlayer?.stop()
                previewPlayer = nil
            }
        }
    }

    private func runTest() {
        testTask?.cancel()
        previewPlayer?.stop()
        isTesting = true
        testStatus = "正在请求合成…"
        let candidate = draftVoice
        testTask = Task { @MainActor in
            do {
                let data = try await HttpTTSClient().synthesize(voice: candidate, text: "纸间阅读，发音人模板试听。", speed: 5)
                guard !Task.isCancelled else { return }
                let player = CloudTTSPlayer()
                previewPlayer = player
                try player.play(data: data)
                testStatus = "测试成功（\(data.count) 字节），正在播放"
            } catch {
                if !Task.isCancelled {
                    testStatus = "测试失败：\(error.localizedDescription)"
                }
            }
            isTesting = false
        }
    }
}
