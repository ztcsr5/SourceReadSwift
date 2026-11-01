import Foundation

enum SourcePlacement: Int, Codable, CaseIterable, Identifiable, Sendable {
    case top = -1, normal = 0, bottom = 1
    var id: Int { rawValue }
    var title: String {
        switch self { case .top: return "置顶"; case .normal: return "普通"; case .bottom: return "置底" }
    }
}

enum SourceLibrarySort: String, Codable, CaseIterable, Identifiable, Sendable {
    case custom, name, enabled, weight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .custom: return "自定义顺序"
        case .name: return "名称"
        case .enabled: return "启用优先"
        case .weight: return "权重优先"
        }
    }
}

/// Library-only metadata, independent of executable source rules. Stored in
/// the same atomic snapshot/backup; reimporting a rule cannot erase user order.
struct SourceOrganization: Codable, Hashable, Sendable {
    var sort: SourceLibrarySort = .custom
    var order: [String] = []
    var placements: [String: SourcePlacement] = [:]
    var groupOverrides: [String: String] = [:]
    var namedGroups: [String] = []

    func placement(for source: BookSource) -> SourcePlacement { placements[source.id] ?? .normal }

    func groups(for source: BookSource) -> [String] {
        Self.splitGroups(groupOverrides[source.id] ?? source.bookSourceGroup ?? "")
    }

    static func splitGroups(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: CharacterSet(charactersIn: ",，;；\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func allGroups(in sources: [BookSource]) -> [String] {
        Array(Set(namedGroups + sources.flatMap { groups(for: $0) })).sorted()
    }

    func ordered(_ sources: [BookSource]) -> [BookSource] {
        var rank: [String: Int] = [:]
        for id in order where rank[id] == nil { rank[id] = rank.count }
        let fallback = Dictionary(sources.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        return sources.sorted { a, b in
            let ap = placement(for: a).rawValue, bp = placement(for: b).rawValue
            if ap != bp { return ap < bp }
            switch sort {
            case .name:
                if a.bookSourceName != b.bookSourceName { return a.bookSourceName < b.bookSourceName }
            case .enabled:
                if a.enabled != b.enabled { return a.enabled }
            case .weight:
                if a.weight != b.weight { return a.weight > b.weight }
            case .custom: break
            }
            let ar = rank[a.id] ?? (order.count + (fallback[a.id] ?? 0))
            let br = rank[b.id] ?? (order.count + (fallback[b.id] ?? 0))
            return ar == br ? a.id < b.id : ar < br
        }
    }

    /// Replace only the slots belonging to a filtered list. Dragging within a
    /// group cannot reorder/lose sources hidden by a search or another group.
    mutating func reorder(_ visibleIDs: [String], in sources: [BookSource]) {
        let valid = Set(sources.map(\.id))
        var seen = Set<String>()
        let requested = visibleIDs.filter { valid.contains($0) && seen.insert($0).inserted }
        let affected = Set(requested)
        var next = requested.makeIterator()
        order = ordered(sources).map { affected.contains($0.id) ? (next.next() ?? $0.id) : $0.id }
        sort = .custom
    }

    mutating func renameGroup(_ old: String, to name: String, sources: [BookSource]) {
        let new = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty, !new.isEmpty, old != new else { return }
        for source in sources where groups(for: source).contains(old) {
            groupOverrides[source.id] = groups(for: source).map { $0 == old ? new : $0 }.joined(separator: ",")
        }
        namedGroups = Array(Set(namedGroups.filter { $0 != old } + [new])).sorted()
    }

    mutating func deleteGroup(_ name: String, sources: [BookSource]) {
        for source in sources where groups(for: source).contains(name) {
            groupOverrides[source.id] = groups(for: source).filter { $0 != name }.joined(separator: ",")
        }
        namedGroups.removeAll { $0 == name }
    }

    mutating func forget(_ ids: Set<String>) {
        order.removeAll { ids.contains($0) }
        for id in ids {
            placements.removeValue(forKey: id)
            groupOverrides.removeValue(forKey: id)
        }
    }
}
