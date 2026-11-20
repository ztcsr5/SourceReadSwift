import Foundation

/// Keeps an authored authentication verdict distinct from saved Cookie state.
struct SourceLoginFeedback: Equatable {
    enum Tone: Equatable { case information, success, warning, failure }

    let title: String
    let message: String
    let tone: Tone

    init(title: String, message: String, tone: Tone) {
        self.title = title
        self.message = message
        self.tone = tone
    }

    init(verification: SourceLoginVerification) {
        message = verification.status == .notConfigured
            ? "书源没有提供登录状态校验，暂时无法确认账号是否有效。请查看书源提示或实际打开正文验证。"
            : verification.message
        switch verification.status {
        case .passed:
            title = "登录验证成功"
            tone = .success
        case .requiresLogin:
            title = "登录未成功"
            tone = .failure
        case .verificationRequired:
            title = "还需要完成验证"
            tone = .warning
        case .blocked:
            title = "登录或访问被拦截"
            tone = .failure
        case .warning:
            title = "登录状态待确认"
            tone = .warning
        case .notConfigured:
            title = "登录状态尚未验证"
            tone = .warning
        }
    }
}
