import Foundation

struct AzureTTSCredentials: Codable, Equatable {
    var region = "eastasia"
    var key = ""

    var isConfigured: Bool {
        region.range(of: #"^[a-z][a-z0-9-]{1,39}$"#, options: .regularExpression) != nil
            && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

final class AzureTTSCredentialsStore {
    private let secrets: SecretStoring
    private let account = "azure-speech-credentials"
    init(secrets: SecretStoring = KeychainSecretStore()) { self.secrets = secrets }
    func load() -> AzureTTSCredentials? {
        guard let raw = secrets.value(for: account), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AzureTTSCredentials.self, from: data)
    }
    func save(_ credentials: AzureTTSCredentials) throws {
        guard credentials.isConfigured else { throw HttpTTSError.server("请填写有效的 Azure 区域及 Speech Key") }
        let data = try JSONEncoder().encode(credentials)
        try secrets.set(String(decoding: data, as: UTF8.self), for: account)
    }
    func clear() throws { try secrets.removeValue(for: account) }
}

enum AzureTTSVoice {
    static let presets: [HttpTTSVoice] = [
        .init(id: -1001, name: "晓萱 · 沉稳女声（御姐风）", url: "azuretts://zh-CN-XiaoxuanNeural"),
        .init(id: -1002, name: "晓伊 · 活泼女声（甜妹风）", url: "azuretts://zh-CN-XiaoyiNeural"),
        .init(id: -1003, name: "晓晓 · 温柔女声", url: "azuretts://zh-CN-XiaoxiaoNeural"),
        .init(id: -1004, name: "云希 · 少年男声", url: "azuretts://zh-CN-YunxiNeural")
    ]

    static func request(voice: HttpTTSVoice, text: String, speed: Int,
                        credentials: AzureTTSCredentials, timeout: TimeInterval) throws -> URLRequest {
        guard credentials.isConfigured else { throw HttpTTSError.server("此音色需先在语音朗读设置中保存自己的 Azure Speech 凭据") }
        guard let preset = presets.first(where: { $0.url == voice.url }),
              let name = preset.url.components(separatedBy: "://").last,
              let url = URL(string: "https://\(credentials.region).tts.speech.microsoft.com/cognitiveservices/v1")
        else { throw HttpTTSError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(credentials.key.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-96kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("SourceReadSwift", forHTTPHeaderField: "User-Agent")
        let rate = (min(max(speed, 0), 10) - 5) * 10
        let ssml = "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xml:lang=\"zh-CN\"><voice name=\"\(name)\"><prosody rate=\"\(rate >= 0 ? "+" : "")\(rate)%\">\(escape(text))</prosody></voice></speak>"
        request.httpBody = Data(ssml.utf8)
        return request
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
