import SwiftUI
import UniformTypeIdentifiers

/// Cloud TTS configuration. Credentials are stored in the Keychain through
/// `CloudTTSCredentialsStore`; only the selected engine lives in UserDefaults.
struct TTSSettingsView: View {
    @AppStorage("reader.ttsEngine") private var engineRawValue: String = TTSEngineKind.local.rawValue
    @AppStorage("reader.httpTTSVoiceID") private var httpVoiceID: Int = HttpTTSVoice.defaultVoiceID

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
    @State private var previewTask: Task<Void, Never>?
    @State private var previewID = UUID()
    @State private var showVoiceImporter = false
    @State private var importedVoiceNames: [String] = []
    @State private var voiceStatusMessage: String?
    @State private var isUpdatingVoices = false
    @State private var showVoiceRemovalConfirmation = false
    @State private var azureRegion = "eastasia"
    @State private var azureKey = ""

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

            if engine == .http {
                Section {
                    Picker("发音人", selection: $httpVoiceID) {
                        ForEach(HttpTTSVoice.defaultVoices) { voice in
                            Text(voice.name).tag(voice.id)
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
                    Text("百度公共预设可能限流；晓萱、晓伊、晓晓、云希使用 Azure 官方服务，需自己的 Speech Key，可能产生服务费用。风格名称仅供选声参考。")
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
        .onAppear {
            if let credentials = AzureTTSCredentialsStore().load() {
                azureRegion = credentials.region; azureKey = credentials.key
            }
            loadCredentials()
            refreshImportedVoices()
            if !HttpTTSVoice.defaultVoices.contains(where: { $0.id == httpVoiceID }),
               let first = HttpTTSVoice.defaultVoices.first {
                httpVoiceID = first.id
            }
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
        HttpTTSVoice.defaultVoices.first(where: { $0.id == httpVoiceID })
            ?? HttpTTSVoice.defaultVoices.first
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
