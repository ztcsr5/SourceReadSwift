import Foundation
import CryptoKit

/// Cloud TTS authentication and protocol helper.
/// Supports constructing RFC1123 timestamped HMAC-SHA256 authentication URLs
/// for cloud speech services such as iFlyTek (科大讯飞) without external dependencies.
public struct CloudTTSProtocol: Sendable {

    public struct XunfeiConfig: Sendable, Equatable {
        public var appId: String
        public var apiKey: String
        public var apiSecret: String
        public var voiceName: String
        public var speed: Int
        public var volume: Int
        public var pitch: Int

        public init(
            appId: String,
            apiKey: String,
            apiSecret: String,
            voiceName: String = "xiaoyan",
            speed: Int = 50,
            volume: Int = 50,
            pitch: Int = 50
        ) {
            self.appId = appId
            self.apiKey = apiKey
            self.apiSecret = apiSecret
            self.voiceName = voiceName
            self.speed = speed
            self.volume = volume
            self.pitch = pitch
        }
    }

    /// Generates a signed WebSocket connection URL for iFlyTek TTS API v2.
    public static func createXunfeiAuthURL(config: XunfeiConfig, date: Date = Date()) -> URL? {
        let host = "tts-api.xfyun.cn"
        let path = "/v2/tts"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let dateString = dateFormatter.string(from: date)

        let signatureOrigin = "host: \(host)\ndate: \(dateString)\nGET \(path) HTTP/1.1"

        let symmetricKey = SymmetricKey(data: Data(config.apiSecret.utf8))
        let signatureData = HMAC<SHA256>.authenticationCode(
            for: Data(signatureOrigin.utf8),
            using: symmetricKey
        )
        let signature = Data(signatureData).base64EncodedString()

        let authOrigin = "api_key=\"\(config.apiKey)\", algorithm=\"hmac-sha256\", headers=\"host date request-line\", signature=\"\(signature)\""
        let authorization = Data(authOrigin.utf8).base64EncodedString()

        var components = URLComponents(string: "wss://\(host)\(path)")
        components?.queryItems = [
            URLQueryItem(name: "authorization", value: authorization),
            URLQueryItem(name: "date", value: dateString),
            URLQueryItem(name: "host", value: host)
        ]
        return components?.url
    }

    /// Constructs the initial JSON frame payload for text-to-speech synthesis.
    public static func createSynthesisPayload(text: String, config: XunfeiConfig) -> Data? {
        let textBase64 = Data(text.utf8).base64EncodedString()
        let payload: [String: Any] = [
            "common": ["app_id": config.appId],
            "business": [
                "aue": "lame",
                "sfl": 1,
                "auf": "audio/L16;rate=16000",
                "vcn": config.voiceName,
                "speed": config.speed,
                "volume": config.volume,
                "pitch": config.pitch,
                "bgs": 0,
                "tte": "UTF8"
            ],
            "data": [
                "status": 2,
                "text": textBase64
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [])
    }
}
