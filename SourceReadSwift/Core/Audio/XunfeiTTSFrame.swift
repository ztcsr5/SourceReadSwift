import Foundation

/// One WebSocket text frame returned by iFlyTek TTS v2.
struct XunfeiTTSFrame: Decodable, Equatable {
    struct Payload: Decodable, Equatable {
        let status: Int?
        let audio: String?
        let ced: String?
    }

    let code: Int
    let message: String?
    let sid: String?
    let data: Payload?

    var isFinal: Bool { data?.status == 2 }

    var decodedAudio: Data? {
        guard let audio = data?.audio, !audio.isEmpty else { return nil }
        return Data(base64Encoded: audio)
    }

    static func decode(_ data: Data) throws -> XunfeiTTSFrame {
        do {
            return try JSONDecoder().decode(XunfeiTTSFrame.self, from: data)
        } catch {
            throw XunfeiTTSError.invalidFrame
        }
    }
}

enum XunfeiTTSError: LocalizedError, Equatable {
    case notConfigured
    case invalidFrame
    case server(code: Int, message: String)
    case emptyAudio
    case timeout
    case connectionClosed
    case invalidResponse
    case playbackUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未配置讯飞语音凭据"
        case .invalidFrame:
            return "云端返回了无法解析的语音帧"
        case .server(let code, let message):
            return "讯飞语音服务错误 \(code)：\(message)"
        case .emptyAudio:
            return "云端未返回音频数据"
        case .timeout:
            return "云端语音请求超时"
        case .connectionClosed:
            return "云端语音连接已关闭"
        case .invalidResponse:
            return "云端语音请求构造失败"
        case .playbackUnavailable:
            return "音频播放失败"
        }
    }
}
