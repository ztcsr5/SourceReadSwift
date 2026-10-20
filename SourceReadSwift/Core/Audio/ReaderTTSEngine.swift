import Foundation

/// Selectable speech backend. Persisted in `reader.ttsEngine`.
enum TTSEngineKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case local
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "系统语音（离线）"
        case .cloud: return "讯飞云端语音"
        }
    }

    var subtitle: String {
        switch self {
        case .local: return "使用 AVSpeechSynthesizer，无需网络"
        case .cloud: return "使用讯飞 WebSocket TTS，需在设置中填写凭据"
        }
    }
}
