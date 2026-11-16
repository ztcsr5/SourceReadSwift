import Foundation

/// Selectable speech backend. Persisted in `reader.ttsEngine`.
enum TTSEngineKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case local
    case cloud
    case http
    /// 导入的本地音频包（按段落序号命名），不合成、不联网。
    case file

    var id: String { rawValue }

    static let synthesisEngines: [Self] = [.local, .cloud, .http]

    var title: String {
        switch self {
        case .local: return "系统语音（离线）"
        case .cloud: return "讯飞云端语音"
        case .http: return "自定义 HTTP 语音"
        case .file: return "预录段落音频（旧版兼容）"
        }
    }

    var subtitle: String {
        switch self {
        case .local: return "直接朗读小说正文，已下载的系统音色可离线使用，无需导入 MP3"
        case .cloud: return "使用讯飞 WebSocket TTS，需在设置中填写凭据"
        case .http: return "将正文发送至你选择的语音服务；音色和凭据由各服务决定"
        case .file: return "只播放已有的段落录音，不会把文字合成为语音；有声书请从书架或书源直接打开"
        }
    }
}
