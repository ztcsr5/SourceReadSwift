import SwiftUI

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
                    .disabled(isTestingHTTP)
                } header: {
                    Text("在线 HTTP 语音")
                } footer: {
                    Text("使用 Legado httpTTS 兼容模板；预设来自 SourceRead httpTTS.json，公共百度接口可能限流。")
                }
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

            Section("合成参数") {
                sliderRow(title: "语速", value: $speed)
                sliderRow(title: "音量", value: $volume)
                sliderRow(title: "音调", value: $pitch)
            }

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
                .disabled(isTesting || !draftCredentials.isConfigured)

                Button(role: .destructive) {
                    self.clearCredentials()
                } label: {
                    Label("清除凭据", systemImage: "trash")
                }
            }

            if let statusMessage {
                Section("状态") {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("语音朗读")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCredentials()
            if !HttpTTSVoice.defaultVoices.contains(where: { $0.id == httpVoiceID }),
               let first = HttpTTSVoice.defaultVoices.first {
                httpVoiceID = first.id
            }
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
        isTesting = true
        statusMessage = "正在请求讯飞合成…"
        Task {
            do {
                let audio = try await self.client.synthesize(text: "纸间阅读，云端语音测试。", credentials: credentials)
                await MainActor.run {
                    let player = CloudTTSPlayer()
                    player.onFinish = {
                        Task { @MainActor in
                            self.statusMessage = "合成成功：\(audio.count) 字节，播放完成"
                        }
                    }
                    player.onError = { error in
                        Task { @MainActor in
                            self.statusMessage = "播放失败：\(error.localizedDescription)"
                        }
                    }
                    self.previewPlayer = player
                    do {
                        try player.play(data: audio)
                        self.statusMessage = "合成成功：\(audio.count) 字节，正在播放"
                    } catch {
                        self.statusMessage = "播放失败：\(error.localizedDescription)"
                    }
                    self.isTesting = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "合成失败：\(error.localizedDescription)"
                    self.isTesting = false
                }
            }
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
        isTestingHTTP = true
        statusMessage = "正在请求 HTTP 语音…"
        Task {
            do {
                let audio = try await self.httpClient.synthesize(
                    voice: voice,
                    text: "纸间阅读，在线语音测试。",
                    speed: 5
                )
                await MainActor.run {
                    let player = CloudTTSPlayer()
                    player.onFinish = {
                        Task { @MainActor in
                            self.statusMessage = "HTTP 语音成功：\(audio.count) 字节，播放完成"
                        }
                    }
                    player.onError = { error in
                        Task { @MainActor in
                            self.statusMessage = "HTTP 语音播放失败：\(error.localizedDescription)"
                        }
                    }
                    self.previewPlayer = player
                    do {
                        try player.play(data: audio)
                        self.statusMessage = "HTTP 语音成功：\(audio.count) 字节，正在播放"
                    } catch {
                        self.statusMessage = "HTTP 语音播放失败：\(error.localizedDescription)"
                    }
                    self.isTestingHTTP = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "HTTP 语音失败：\(error.localizedDescription)"
                    self.isTestingHTTP = false
                }
            }
        }
    }
}
