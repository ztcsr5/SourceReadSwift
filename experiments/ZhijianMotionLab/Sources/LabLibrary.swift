import SwiftUI

/// A small, isolated demo store. No network, secrets, production data or fake history.
@MainActor final class LabLibrary: ObservableObject {
    let books = LabBook.samples
    @Published private(set) var snapshot: LabSnapshot
    @Published private(set) var persistenceMessage: String?
    @Published var minimizesMotion: Bool { didSet { preferences.set(minimizesMotion, forKey: "lab.minimizesMotion") } }
    @Published var usesImmersiveBackground: Bool { didSet { preferences.set(usesImmersiveBackground, forKey: "lab.immersiveBackground") } }
    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        minimizesMotion = preferences.bool(forKey: "lab.minimizesMotion")
        usesImmersiveBackground = (preferences.object(forKey: "lab.immersiveBackground") as? Bool) ?? true
        if let encoded = preferences.data(forKey: "lab.snapshot") {
            do { snapshot = try JSONDecoder().decode(LabSnapshot.self, from: encoded) }
            catch { snapshot = .init(); persistenceMessage = "演示记录无法读取，原记录未覆盖：\(error.localizedDescription)" }
        } else { snapshot = .init() }
    }

    func position(for book: LabBook) -> LabPosition {
        let recorded = snapshot.positions[book.id] ?? .init()
        return LabPosition(chapter: min(max(recorded.chapter, 0), max(book.chapters.count - 1, 0)),
                           paragraph: min(max(recorded.paragraph, 0), max(book.paragraphs.count - 1, 0)))
    }

    func savePosition(book: LabBook, chapter: Int, paragraph: Int) {
        var next = snapshot
        next.positions[book.id] = LabPosition(chapter: min(max(chapter, 0), max(book.chapters.count - 1, 0)),
                                            paragraph: min(max(paragraph, 0), max(book.paragraphs.count - 1, 0)))
        commit(next)
    }

    func saveQuote(book: LabBook, paragraph: Int) {
        guard book.paragraphs.indices.contains(paragraph) else { return }
        let text = book.paragraphs[paragraph]
        guard !snapshot.quotes.contains(where: { $0.bookID == book.id && $0.text == text }) else { return }
        var next = snapshot
        next.quotes.insert(.init(id: UUID(), bookID: book.id, bookTitle: book.title, text: text, createdAt: Date()), at: 0)
        next.quotes = Array(next.quotes.prefix(200))
        commit(next)
    }

    func deleteQuote(_ id: UUID) {
        var next = snapshot; next.quotes.removeAll { $0.id == id }; commit(next)
    }

    func reset() { commit(.init()) }

    private func commit(_ next: LabSnapshot) {
        do {
            let encoded = try JSONEncoder().encode(next)
            preferences.set(encoded, forKey: "lab.snapshot")
            snapshot = next; persistenceMessage = nil
        } catch { persistenceMessage = "保存演示记录失败：\(error.localizedDescription)" }
    }
}
