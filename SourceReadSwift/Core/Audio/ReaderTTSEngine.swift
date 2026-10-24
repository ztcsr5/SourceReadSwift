import Foundation

/// Selectable speech backend. Persisted in `reader.ttsEngine`.
enum TTSEngineKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case local
    case cloud
    case http
    /// 导入的本地音频包（按段落序号命名），不合成、不联网。
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "系统语音（离线）"
        case .cloud: return "讯飞云端语音"
        case .http: return "在线 HTTP 语音（百度）"
        case .file: return "本地声音（导入音频）"
        }
    }

    var subtitle: String {
        switch self {
        case .local: return "使用 AVSpeechSynthesizer，无需网络"
        case .cloud: return "使用讯飞 WebSocket TTS，需在设置中填写凭据"
        case .http: return "使用 Legado httpTTS 兼容模板，无需密钥"
        case .file: return "播放自己导入的音频文件，文件名用段落序号（0.mp3、1.mp3…）"
        }
    }
}
