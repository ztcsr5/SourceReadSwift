import UIKit

#if DEBUG
/// Offline fixtures are reachable only by an explicit UI-test launch argument and isolated store.
@MainActor enum FloatingDeskRegressionLaunch {
    static func makeAppState() -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("floating-desk-ui-" + UUID().uuidString)
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: root),
            groupPersistence: BookshelfGroupPersistence(rootURL: root))
        let chapters = OnboardingClassicBook.makeWelcomeBook().chapters
        for (index, title) in ["白昼之后，我们把很长很长的信写给远方与尚未相逢的人", "月色与六便士", "山海来信"].enumerated() {
            let cover = index == 0 ? nil : makeCover(at: root, index: index, title: title)
            shelf.addLocalTextBook(LocalTextBook(title: title, author: "离线验收样本", chapters: chapters, coverURL: cover))
            if let book = shelf.books.first { shelf.markReaderOpened(bookID: book.id) }
        }
        return AppState(sourceStore: SourceStore(persistence: SourcePersistence(rootURL: root)), bookshelfStore: shelf)
    }

    private static func makeCover(at root: URL, index: Int, title: String) -> URL? {
        let path = root.appendingPathComponent("desk-cover-\(index).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 336, height: 448)).image { context in
            let bounds = CGRect(x: 0, y: 0, width: 336, height: 448)
            (index == 1 ? UIColor(red: 0.91, green: 0.86, blue: 0.75, alpha: 1) : UIColor(red: 0.16, green: 0.24, blue: 0.30, alpha: 1)).setFill()
            context.fill(bounds)
            if index == 2 {
                UIColor(red: 0.74, green: 0.77, blue: 0.69, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 204, y: 64, width: 64, height: 64))
                for row in 0..<5 {
                    UIColor(white: CGFloat(row) * 0.07 + 0.18, alpha: 1).setFill()
                    let ridge = UIBezierPath()
                    ridge.move(to: CGPoint(x: 0, y: 200 + row * 32))
                    ridge.addCurve(to: CGPoint(x: 336, y: 190 + row * 40),
                        controlPoint1: CGPoint(x: 100, y: 100 + row * 40), controlPoint2: CGPoint(x: 180, y: 300 + row * 24))
                    ridge.addLine(to: CGPoint(x: 336, y: 448)); ridge.addLine(to: CGPoint(x: 0, y: 448)); ridge.close(); ridge.fill()
                }
            }
            let ink: UIColor = index == 1 ? .darkGray : .white
            (title as NSString).draw(in: CGRect(x: 32, y: 40, width: 272, height: 180), withAttributes: [
                .font: UIFont.systemFont(ofSize: 36, weight: .medium), .foregroundColor: ink])
            ("纸间 · 离线视觉验收" as NSString).draw(at: CGPoint(x: 32, y: 398), withAttributes: [
                .font: UIFont.systemFont(ofSize: 15), .foregroundColor: ink.withAlphaComponent(0.8)])
        }
        do { try image.pngData()?.write(to: path); return path }
        catch { assertionFailure("Could not write isolated floating-desk cover: \(error)"); return nil }
    }
}
#endif
