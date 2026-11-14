import SwiftUI
import UIKit

/// A fixed-height native table can locate any chapter without creating or
/// measuring the rows before it. Position the table at its first real layout.
struct ReaderChapterDirectoryList: UIViewRepresentable {
    struct Projection: Equatable {
        let chapters: [BookChapter]
        let entries: [LocalTextNavigationEntry]
        let currentChapter: Int
        let upperBound: Int
        let readyChapters: Set<Int>
        let canLoadChapter: Bool
    }

    let projection: Projection
    let location: IndexPath?
    let locationRequest: UUID
    let ink: Color
    let accent: Color
    let selectChapter: (Int) -> Void
    let selectEntry: ((LocalTextNavigationEntry) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    func makeUIView(context: Context) -> DirectoryTable {
        let table = DirectoryTable(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.estimatedRowHeight = 0
        table.estimatedSectionHeaderHeight = 0
        table.estimatedSectionFooterHeight = 0
        table.sectionHeaderTopPadding = 0
        table.contentInsetAdjustmentBehavior = .never
        table.keyboardDismissMode = .onDrag
        table.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        table.accessibilityIdentifier = "reader.toc.list"
        table.register(DirectoryCell.self, forCellReuseIdentifier: DirectoryCell.reuseID)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.didLayout = { [weak coordinator = context.coordinator] table in
            coordinator?.positionIfReady(in: table)
        }
        return table
    }

    func updateUIView(_ table: DirectoryTable, context: Context) {
        context.coordinator.update(self, table: table)
    }

    @MainActor
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        private var owner: ReaderChapterDirectoryList
        private var didLoad = false
        private var userScrolled = false
        private var pendingLocation: IndexPath?

        init(owner: ReaderChapterDirectoryList) {
            self.owner = owner
            pendingLocation = owner.location
        }

        func update(_ next: ReaderChapterDirectoryList, table: DirectoryTable) {
            let requested = owner.locationRequest != next.locationRequest
            let locationChanged = owner.location != next.location
            let changed = owner.projection != next.projection
                || owner.ink != next.ink || owner.accent != next.accent
                || (owner.selectEntry != nil) != (next.selectEntry != nil)
            owner = next
            if requested { userScrolled = false }
            if requested || (!userScrolled && locationChanged) { pendingLocation = next.location }
            if !didLoad || changed {
                didLoad = true
                table.separatorColor = UIColor(next.ink).withAlphaComponent(0.14)
                table.reloadData()
            }
            positionIfReady(in: table)
        }

        func positionIfReady(in table: DirectoryTable) {
            guard let location = pendingLocation, table.window != nil, table.bounds.width > 1,
                  table.bounds.height > 1, !table.isDragging,
                  location.section < table.numberOfSections,
                  location.row < table.numberOfRows(inSection: location.section) else { return }
            pendingLocation = nil
            table.scrollToRow(at: location, at: .middle, animated: false)
        }

        func numberOfSections(in tableView: UITableView) -> Int { 2 }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            section == 0 ? owner.projection.chapters.count : owner.projection.entries.count
        }

        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            section == 1 && !owner.projection.entries.isEmpty ? "页面内目录" : nil
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            userScrolled = true
            pendingLocation = nil
        }

        func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: DirectoryCell.reuseID, for: path) as? DirectoryCell
            else { return UITableViewCell(style: .default, reuseIdentifier: nil) }
            let ink = UIColor(owner.ink)
            if path.section == 0 {
                let chapter = owner.projection.chapters[path.row]
                let isCurrent = chapter.index == owner.projection.currentChapter
                cell.configure(title: chapter.title, number: chapter.index + 1, ink: isCurrent ? UIColor(owner.accent) : ink,
                               status: isCurrent ? .current : (canSelect(chapter) ? .chapter : .unavailable))
                cell.accessibilityIdentifier = "reader.toc.chapter.\(chapter.index)"
            } else {
                let entry = owner.projection.entries[path.row]
                cell.configure(title: entry.title, number: path.row + 1, ink: ink,
                               status: canSelect(entry) ? .entry : .unavailable)
                cell.accessibilityIdentifier = "reader.toc.entry.\(path.row)"
            }
            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
            tableView.deselectRow(at: path, animated: false)
            if path.section == 0 {
                guard owner.projection.chapters.indices.contains(path.row) else { return }
                let chapter = owner.projection.chapters[path.row]
                if canSelect(chapter) { owner.selectChapter(chapter.index) }
            } else {
                guard owner.projection.entries.indices.contains(path.row) else { return }
                let entry = owner.projection.entries[path.row]
                if canSelect(entry) { owner.selectEntry?(entry) }
            }
        }

        private func canSelect(_ chapter: BookChapter) -> Bool {
            let projection = owner.projection
            return chapter.index != projection.currentChapter && (projection.canLoadChapter
                || projection.readyChapters.contains(chapter.index)
                || (chapter.index >= 0 && chapter.index < projection.upperBound))
        }

        private func canSelect(_ entry: LocalTextNavigationEntry) -> Bool {
            owner.selectEntry != nil && entry.chapterIndex != nil
        }
    }

    final class DirectoryTable: UITableView {
        var didLayout: ((DirectoryTable) -> Void)?

        override func layoutSubviews() {
            // Keep heights exact for any supported text size, not UIKit estimates.
            let height = UIFontMetrics.default.scaledValue(for: 48, compatibleWith: traitCollection)
            if rowHeight != height { rowHeight = height }
            super.layoutSubviews()
            didLayout?(self)
        }
    }

    private final class DirectoryCell: UITableViewCell {
        static let reuseID = "chapter-directory-row"
        enum Status: Equatable { case chapter, current, entry, unavailable }

        private let numberLabel = UILabel()
        private let heading = UILabel()
        private let marker = UIImageView()

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            backgroundColor = .clear
            isAccessibilityElement = true
            numberLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            heading.adjustsFontForContentSizeCategory = true
            heading.lineBreakMode = .byTruncatingTail
            marker.contentMode = .center
            let row = UIStackView(arrangedSubviews: [numberLabel, heading, marker])
            row.spacing = 12
            row.alignment = .center
            row.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                row.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                numberLabel.widthAnchor.constraint(equalToConstant: 44),
                marker.widthAnchor.constraint(equalToConstant: 20)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Create directory cells through the native table") }

        func configure(title: String, number: Int, ink: UIColor, status: Status) {
            let isCurrent = status == .current
            let isUnavailable = status == .unavailable
            numberLabel.text = String(number)
            numberLabel.textColor = ink.withAlphaComponent(0.72)
            heading.text = title
            heading.font = .preferredFont(forTextStyle: .body)
            heading.textColor = ink
            marker.tintColor = ink
            marker.image = isCurrent ? UIImage(systemName: "checkmark.circle.fill")
                : status == .entry ? UIImage(systemName: "arrow.down.right") : nil
            accessibilityLabel = "第 \(number) 项，\(title)"
            accessibilityValue = isCurrent ? "当前章" : nil
            accessibilityTraits = isCurrent ? [.button, .selected, .notEnabled] : (isUnavailable ? [.button, .notEnabled] : .button)
            selectionStyle = isCurrent || isUnavailable ? .none : .default
        }
    }
}
