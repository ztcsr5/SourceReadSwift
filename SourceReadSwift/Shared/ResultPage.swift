import Foundation

enum ResultPage {
    static func slice<Element>(_ elements: [Element], page: Int, size: Int = 20) -> [Element] {
        let size = max(1, size)
        let last = max(0, (elements.count - 1) / size)
        let start = min(max(0, page), last) * size
        return Array(elements[start..<min(elements.count, start + size)])
    }
}
