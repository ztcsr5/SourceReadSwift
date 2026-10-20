import Foundation

/// Selectable speech backend. Persisted in `reader.ttsEngine`.
enum TTSEngineKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case local
    case cloud
    case http

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "系统语音（离线）"
        case .cloud: return "讯飞云端语音"
        case .http: return "在线 HTTP 语音（百度）"
        }
    }

    var subtitle: String {
        switch self {
        case .local: return "使用 AVSpeechSynthesizer，无需网络"
        case .cloud: return "使用讯飞 WebSocket TTS，需在设置中填写凭据"
        case .http: return "使用 Legado httpTTS 兼容模板，无需密钥"
        }
    }
}
