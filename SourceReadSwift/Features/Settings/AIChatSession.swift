import SwiftUI
import UIKit
import ImageIO

struct AIChatSubmission: Identifiable {
    let id = UUID()
    let config: AIChatConfiguration
    let key: String
    let history: [AIChatMessage]
    let byteCount: Int
}

@MainActor
final class AIChatSession: ObservableObject {
    @Published private(set) var messages: [AIChatMessage] = []
    @Published private(set) var isSending = false
    @Published var status: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let client: AIChatClient

    init(client: AIChatClient = AIChatClient()) { self.client = client }

    func prepare(text: String, attachments: [AIChatAttachment], config: AIChatConfiguration,
                 credentials: AIChatCredentials) throws -> AIChatSubmission {
        guard !isSending else { throw AIChatFailure.configuration }
        guard let key = credentials.key(for: config) else { throw AIChatFailure.missingKey }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || !attachments.isEmpty else { throw AIChatFailure.invalidAttachment }
        let history = messages + [AIChatMessage(role: .user, text: clean, attachments: attachments)]
        let request = try AIChatClient.request(config: config, key: key, messages: history)
        return AIChatSubmission(config: config, key: key, history: history, byteCount: request.httpBody?.count ?? 0)
    }

    func send(_ submission: AIChatSubmission) {
        guard !isSending else { return }
        let revision = UUID(); generation = revision
        messages = submission.history; isSending = true; status = "正在请求，不会自动重发…"
        task = Task { [weak self, client] in
            do {
                let reply = try await client.reply(config: submission.config, key: submission.key, messages: submission.history)
                guard let self, self.generation == revision, !Task.isCancelled else { return }
                self.messages.append(.init(role: .assistant, text: reply, modelName: submission.config.model)); self.status = nil; self.isSending = false
            } catch {
                guard let self, self.generation == revision else { return }
                self.isSending = false
                self.status = Task.isCancelled ? "已停止。请求可能已被服务商计费，不会自动重发。" : error.localizedDescription
            }
        }
    }

    func stop() {
        generation = UUID(); task?.cancel(); task = nil
        if isSending { status = "已停止。请求可能已被服务商计费，不会自动重发。" }
        isSending = false
    }

    func clear() { stop(); messages = []; status = nil }
}

enum AIChatAttachmentLoader {
    static func load(_ url: URL) throws -> AIChatAttachment {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes = Data()
        while bytes.count <= 2_000_000 {
            guard let chunk = try handle.read(upToCount: min(65_536, 2_000_001 - bytes.count)), !chunk.isEmpty else { break }
            bytes.append(chunk)
        }
        guard !bytes.isEmpty, bytes.count <= 2_000_000 else { throw AIChatFailure.invalidAttachment }
        if let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetType(source) != nil {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                          kCGImageSourceThumbnailMaxPixelSize: 1280,
                                          kCGImageSourceCreateThumbnailWithTransform: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw AIChatFailure.invalidAttachment }
            return try jpeg(UIImage(cgImage: image), name: url.lastPathComponent)
        }
        guard let text = String(data: bytes, encoding: .utf8), !text.contains("\0") else { throw AIChatFailure.invalidAttachment }
        return AIChatAttachment(name: url.lastPathComponent, payload: .text(AIChatAttachmentPrivacy.scrubJSON(text)))
    }

    static func jpeg(_ image: UIImage, name: String) throws -> AIChatAttachment {
        // Redrawing strips metadata and bounds upload size and decoding work.
        let scale = min(1280 / max(image.size.width, image.size.height), 1)
        guard scale.isFinite, scale > 0 else { throw AIChatFailure.invalidAttachment }
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let clean = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = clean.jpegData(compressionQuality: 0.8), data.count <= 2_000_000 else { throw AIChatFailure.invalidAttachment }
        return AIChatAttachment(name: name, payload: .jpeg(data))
    }
}
