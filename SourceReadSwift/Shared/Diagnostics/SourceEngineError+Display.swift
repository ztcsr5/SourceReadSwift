import Foundation

extension SourceEngineError: LocalizedError {
    var displayMessage: String {
        switch self {
        case .unsupported(let text), .invalidSource(let text), .network(let text),
             .rule(let text), .javascript(let text), .blocked(let text), .empty(let text):
            return text
        }
    }

    public var errorDescription: String? {
        displayMessage
    }
}

