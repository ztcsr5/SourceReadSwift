import SwiftUI
import UIKit

/// 一次阅读请求。放在 `AppState` 里，由 `RootTabView` 的覆盖层呈现。
///
/// 为什么不再用 `navigationDestination`：
/// 阅读器一旦是 NavigationStack 的 destination，侧滑开始那一刻 SwiftUI 就会
/// 拆掉它、恢复主页 chrome、重建书架 —— 提前浮现、闪动、主页重载全部由此而来。
/// 覆盖层让主页永远活着，没有 pop，也就没有那一整套冲突。
struct ReaderOverlayRequest: Identifiable {
    let book: BookshelfBook
    var initialBookmark: ReaderBookmark?
    var initialChapterIndex: Int?
    var coverFrame: UIImage?

    var id: String {
        book.id + "|" + (initialBookmark?.id ?? "") + "|" + String(initialChapterIndex ?? -1)
    }
}

/// 覆盖在 tab 之上的阅读层。
///
/// 开：从底部推入；关：左缘拖拽或阅读器自己的返回按钮，反向推回。
/// 手势用现成的 `ReaderExitSwipeBridge`（`UIScreenEdgePanGestureRecognizer`），
/// 它只挂在阅读子树里，不会和主页抢，也不需要 `require(toFail:)` 任何原生 pop。
struct ReaderOverlayLayer: View {
    let request: ReaderOverlayRequest
    let onClose: () -> Void
    @EnvironmentObject private var appState: AppState

    var body: some View {
        BookshelfReaderGatewayView(
            book: request.book,
            initialBookmark: request.initialBookmark,
            initialChapterIndex: request.initialChapterIndex,
            onRequestExit: onClose
        )
        // 阅读层不走导航栈，chrome 由它自己声明，不存在"恢复"这一步。
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .background(
            ReaderExitSwipeBridge(enabled: true, onExit: onClose, prefersSystemReturn: false)
        )
        .ignoresSafeArea()
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(20)
    }
}
