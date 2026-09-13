import Foundation
import SwiftUI

public struct BookReaderOverride: Codable, Equatable, Sendable {
    public var readerMode: ReaderMode?
    public var fontFamily: ReaderFontFamily?
    public var fontSize: CGFloat?
    public var lineSpacing: CGFloat?
    public var background: ReaderBackground?

    public init(
        readerMode: ReaderMode? = nil,
        fontFamily: ReaderFontFamily? = nil,
        fontSize: CGFloat? = nil,
        lineSpacing: CGFloat? = nil,
        background: ReaderBackground? = nil
    ) {
        self.readerMode = readerMode
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.background = background
    }

    public var hasAnyOverride: Bool {
        readerMode != nil || fontFamily != nil || fontSize != nil || lineSpacing != nil || background != nil
    }
}

@MainActor
public final class ReaderOverrideStore: ObservableObject {
    public static let shared = ReaderOverrideStore()

    private let storageKey = "book_reader_overrides_v1"
    @Published private var overrides: [String: BookReaderOverride] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: BookReaderOverride].self, from: data) {
            self.overrides = decoded
        }
    }

    public func override(for bookID: String) -> BookReaderOverride? {
        overrides[bookID]
    }

    public func setOverride(_ override: BookReaderOverride, for bookID: String) {
        if override.hasAnyOverride {
            overrides[bookID] = override
        } else {
            overrides.removeValue(forKey: bookID)
        }
        save()
    }

    public func clearOverride(for bookID: String) {
        overrides.removeValue(forKey: bookID)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
