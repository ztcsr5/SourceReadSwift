import Foundation

/// Errors surfaced by the Legado-compatible HTTP TTS pipeline.  Keeping them
/// typed lets the reader fall back to the local voice with a readable banner
/// instead of silently playing nothing.
enum HttpTTSError: LocalizedError, Equatable {
    case invalidRequest
    case emptyText
    case httpStatus(Int)
    case emptyAudio
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "HTTP 语音请求模板无法解析"
        case .emptyText:
            return "待朗读文本为空"
        case .httpStatus(let code):
            return "HTTP 语音服务返回状态码 \(code)"
        case .emptyAudio:
            return "HTTP 语音服务返回空音频"
        case .server(let message):
            return "HTTP 语音服务错误：\(message)"
        }
    }
}

/// Seam used by tests to avoid real network calls.
protocol HttpTTSRequesting {
    func httpTTSData(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HttpTTSRequesting {
    func httpTTSData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Executes an `HttpTTSVoice` template and returns the audio payload.
/// The request template is resolved through `JSCoreRuntime`, matching the
/// `{{java.encodeURI(...)}}` syntax used by Legado `httpTTS.json`.
final class HttpTTSClient {
    private let requester: HttpTTSRequesting
    private let timeout: TimeInterval

    init(requester: HttpTTSRequesting = URLSession.shared, timeout: TimeInterval = 20) {
        self.requester = requester
        self.timeout = timeout
    }

    func synthesize(voice: HttpTTSVoice, text: String, speed: Int = 5) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HttpTTSError.emptyText }
        let clampedSpeed = min(max(speed, 0), 10)
        guard let resolved = voice.resolveRequest(speakText: trimmed, speakSpeed: clampedSpeed) else {
            throw HttpTTSError.invalidRequest
        }

        var request = URLRequest(url: resolved.url)
        request.httpMethod = resolved.method
        request.timeoutInterval = timeout
        for (key, value) in resolved.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body = resolved.body {
            request.httpBody = Data(body.utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response) = try await requester.httpTTSData(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw HttpTTSError.httpStatus(http.statusCode)
            }
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if contentType.contains("json") || contentType.hasPrefix("text/") {
                throw HttpTTSError.server(Self.snippet(from: data))
            }
        }
        guard !data.isEmpty else { throw HttpTTSError.emptyAudio }
        // Baidu occasionally replies 200 with a JSON error object and an
        // octet-stream content type; never feed that into AVAudioPlayer.
        if let first = data.first, first == 0x7B || first == 0x5B {
            throw HttpTTSError.server(Self.snippet(from: data))
        }
        return data
    }

    private static func snippet(from data: Data) -> String {
        let text = String(data: Data(data.prefix(300)), encoding: .utf8) ?? ""
        return text.isEmpty ? "响应内容为空" : text
    }
}
