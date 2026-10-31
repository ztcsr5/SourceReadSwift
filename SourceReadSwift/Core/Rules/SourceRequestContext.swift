import Foundation

enum SourceRequestContext {
    /// Probe policy belongs to the task tree, not the shared production engine.
    @TaskLocal static var isDiagnostic = false
}
