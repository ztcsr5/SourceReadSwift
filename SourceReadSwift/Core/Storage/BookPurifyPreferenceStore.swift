import Foundation
import CryptoKit

/// Stores authored purification choices per source and book, including books outside the shelf.
final class BookPurifyPreferenceStore: @unchecked Sendable {
    static let shared = BookPurifyPreferenceStore(defaults: .standard)
    private let defaults: UserDefaults?
    private let lock = NSLock()
    private var choices: [String: Bool] = [:]

    init(defaults: UserDefaults? = nil) { self.defaults = defaults }

    func value(sourceURL: String, bookURL: String) -> Bool? {
        guard !bookURL.isEmpty else { return nil }
        let key = preferenceKey(sourceURL: sourceURL, bookURL: bookURL)
        lock.lock(); defer { lock.unlock() }
        return choices[key] ?? (defaults?.object(forKey: key) as? Bool)
    }

    /// Seeds a model's older choice only when no rule has stored a choice for this book.
    func resolve(sourceURL: String, bookURL: String, inherited: Bool?) -> Bool? {
        guard !bookURL.isEmpty else { return inherited }
        let key = preferenceKey(sourceURL: sourceURL, bookURL: bookURL)
        lock.lock(); defer { lock.unlock() }
        if let current = choices[key] ?? (defaults?.object(forKey: key) as? Bool) { return current }
        guard let inherited else { return nil }
        if let defaults { defaults.set(inherited, forKey: key) }
        else { choices[key] = inherited }
        return inherited
    }

    func set(_ enabled: Bool, sourceURL: String, bookURL: String) {
        guard !bookURL.isEmpty else { return }
        let key = preferenceKey(sourceURL: sourceURL, bookURL: bookURL)
        lock.lock(); defer { lock.unlock() }
        guard (choices[key] ?? (defaults?.object(forKey: key) as? Bool)) != enabled else { return }
        if let defaults { defaults.set(enabled, forKey: key) }
        else { choices[key] = enabled }
    }

    private func preferenceKey(sourceURL: String, bookURL: String) -> String {
        let identity = "\(sourceURL.utf8.count):\(sourceURL)\(bookURL)"
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "source.bookPurify." + digest
    }
}
