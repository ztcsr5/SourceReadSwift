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
    /// 打开瞬间书封在屏幕坐标系里的位置，用来做起止几何。拿不到时用合成矩形。
    var coverRect: CGRect?
    var coverImage: UIImage?

    var id: String {
        book.id + "|" + (initialBookmark?.id ?? "") + "|" + String(initialChapterIndex ?? -1)
    }
}

/// 覆盖在 tab 之上的阅读层。
///
/// 进度 p 驱动全部几何：封面矩形 → 全屏。跟手时由边缘拖拽直接写 p，
/// 松手后补一段弹簧。正文与封面各有独立的显隐曲线，避免"文字跟着缩放"。
///
/// 手势只用左缘 `UIScreenEdgePanGestureRecognizer`，不接管内容区，
/// 因此不会和正文的横向翻页抢手势。
struct ReaderOverlayLayer: View {
    let request: ReaderOverlayRequest
    let onClose: () -> Void
    @EnvironmentObject private var appState: AppState
    @AppMotion private var motion
    @StateObject private var transition = ReaderTransition(reducesMotion: false)
    @State private var width: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let cover = request.coverRect ?? defaultCoverRect(in: screen)
            let rect = ReaderTransitionPolicy.targetRect(cover: cover, screen: screen,
                                                         progress: transition.progress)
            let scaleX = screen.width > 0 ? rect.width / screen.width : 1
            let scaleY = screen.height > 0 ? rect.height / screen.height : 1
            let corner = ReaderTransitionPolicy.cornerRadius(progress: transition.progress,
                                                             compact: 12, full: 0)

            ZStack {
                // 阅读内容始终按最终尺寸排版，只做整体缩放：
                // 布局尺寸不变，WebView 不会因为动画反复重排。
                BookshelfReaderGatewayView(
                    book: request.book,
                    initialBookmark: request.initialBookmark,
                    initialChapterIndex: request.initialChapterIndex,
                    onRequestExit: close
                )
                .frame(width: screen.width, height: screen.height)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
                .offset(x: rect.midX - screen.width / 2, y: rect.midY - screen.height / 2)
                .shadow(color: .black.opacity(0.22 * (1 - transition.progress)),
                        radius: 24 * (1 - transition.progress), x: 0, y: 8)

                // 封面盖在上面淡出：进入时看到的是封面放大，落位后由正文接管。
                if let image = request.coverImage,
                   ReaderTransitionPolicy.coverOpacity(progress: transition.progress) > 0.01 {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: rect.width, height: rect.height)
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        .opacity(ReaderTransitionPolicy.coverOpacity(progress: transition.progress))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: screen.width, height: screen.height)
            .background(
                ReaderExitSwipeBridge(
                    enabled: true,
                    // 覆盖层没有导航栈 pop，onExit 保持空实现；
                    // 关闭由 onEnded 的判定驱动，才能先播完动画再移除。
                    onExit: {},
                    prefersSystemReturn: false,
                    onChanged: { dx in
                        transition.drag(translation: max(dx, 0), width: max(width, 1))
                    },
                    onEnded: { dx, vx in
                        let finish = ReaderTransitionPolicy.shouldDismiss(
                            translation: dx, velocity: vx, width: max(width, 1))
                        transition.endDrag(finish: finish, onFinish: close)
                    }
                )
            )
            .onAppear {
                width = screen.width
                transition.reducesMotion = motion.reducesMotion
                transition.open()
            }
            .onChange(of: screen.width) { width = $0 }
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .zIndex(20)
    }

    private func defaultCoverRect(in size: CGSize) -> CGRect {
        // 拿不到真实位置时的退化几何：偏左上、竖版比例，和书架卡片同构。
        let w = size.width * 0.30
        let h = w * 1.42
        return CGRect(x: size.width * 0.08, y: size.height * 0.20, width: w, height: h)
    }

    private func close() {
        onClose()
    }
}
