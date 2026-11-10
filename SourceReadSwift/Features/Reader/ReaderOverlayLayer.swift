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
    /// 调用方若已知封面矩形可直接给；否则由 `ReaderCoverAnchorStore` 提供。
    var coverRect: CGRect?
    var coverImage: UIImage?

    var id: String {
        book.id + "|" + (initialBookmark?.id ?? "") + "|" + String(initialChapterIndex ?? -1)
    }
}

/// 覆盖在 tab 之上的阅读层。
///
/// 进度 p 驱动全部几何：封面矩形 → 全屏。跟手时由边缘拖拽直接写 p，
/// 松手后补一段弹簧。正文就绪前一律由封面/纸面遮挡，不会露出空白 WebView。
struct ReaderOverlayLayer: View {
    let request: ReaderOverlayRequest
    let onClose: () -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject private var anchors = ReaderCoverAnchorStore.shared
    @StateObject private var transition = ReaderTransition(reducesMotion: false)

    @State private var contentReady = false
    @State private var screenWidth: CGFloat = 0
    /// 只允许一次关闭，避免 onExit 与 onEnded 双触发。
    @State private var didRequestClose = false

    private var resolvedCoverRect: CGRect? {
        anchors.rect(for: request.book.id) ?? request.coverRect
    }

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let p = transition.progress
            let cover = resolvedCoverRect
            let rect = ReaderTransitionPolicy.targetRect(
                cover: cover ?? fallbackCoverRect(in: screen), screen: screen, progress: p)
            let scaleX: CGFloat = screen.width > 0 ? rect.width / screen.width : 1
            let scaleY: CGFloat = screen.height > 0 ? rect.height / screen.height : 1
            let corner: CGFloat = ReaderTransitionPolicy.cornerRadius(progress: p, compact: 12, full: 0)
            let offsetX: CGFloat = rect.midX - screen.width / 2
            let offsetY: CGFloat = rect.midY - screen.height / 2
            let shadowOpacity: Double = 0.22 * Double(1 - p)
            let shadowRadius: CGFloat = 24 * (1 - p)
            // 正文未就绪时封面保持不透明：不允许出现空白 WebView，
            // 也不允许封面在等待正文时消失。
            let veilOpacity: Double = contentReady
                ? ReaderTransitionPolicy.coverOpacity(progress: p)
                : 1

            ZStack {
                BookshelfReaderGatewayView(
                    book: request.book,
                    initialBookmark: request.initialBookmark,
                    initialChapterIndex: request.initialChapterIndex,
                    onRequestExit: close
                )
                .frame(width: screen.width, height: screen.height)
                // 真实挂载到达探针与 ready 信号：之前只有 navigationDestination
                // 路径包了它，覆盖层路径缺失，导致 UI 回归无法观察到真实手势/就绪状态。
                .readerOpeningPresentation(for: request.book, coverFrame: request.coverImage)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
                .offset(x: offsetX, y: offsetY)
                .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 8)
                // 覆盖层路径不需要隐藏/恢复 tab chrome，用标记与旧导航路径隔离。
                .environment(\.readerPresentedAsOverlay, true)
                .readerReadySignal { ready in
                    guard ready != contentReady else { return }
                    contentReady = ready
                }

                // 封面 / 纸面遮罩
                if veilOpacity > 0.001 {
                    Group {
                        if let image = request.coverImage {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Color(uiColor: .secondarySystemBackground)
                        }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .opacity(veilOpacity)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: screen.width, height: screen.height)
            .background(
                ReaderExitSwipeBridge(
                    enabled: true,
                    // 覆盖层没有导航栈 pop；关闭由 onEnded 的判定驱动，
                    // onExit 保持空实现，避免两条路径重复退出。
                    onExit: {},
                    prefersSystemReturn: false,
                    onChanged: { dx in
                        transition.drag(translation: max(dx, 0), width: max(screenWidth, 1))
                    },
                    onEnded: { dx, vx, wasCancelled in
                        let finish = !wasCancelled && ReaderTransitionPolicy.shouldDismiss(
                            translation: dx, velocity: vx, width: max(screenWidth, 1))
                        transition.endDrag(finish: finish) {
                            anchors.endTransition()
                            close()
                        }
                        if !finish { anchors.endTransition() }
                    }
                )
            )
            .onAppear {
                screenWidth = screen.width
                transition.reducesMotion = systemReduceMotion
                // 有真实封面位置才隐藏源封面；降级路径不动源视图。
                if resolvedCoverRect != nil { anchors.beginTransition(bookID: request.book.id) }
                transition.open()
            }
            .onChange(of: screen.width) { screenWidth = $0 }
        }
        .ignoresSafeArea()
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .zIndex(20)
    }

    private func fallbackCoverRect(in size: CGSize) -> CGRect {
        // 没有可靠坐标时的**降级**起点：偏左上、竖版比例。
        // 这不是共享元素转场，只为让缩放有个合理落点。
        let w = size.width * 0.30
        let h = w * 1.42
        return CGRect(x: size.width * 0.08, y: size.height * 0.20, width: w, height: h)
    }

    private func close() {
        guard !didRequestClose else { return }
        didRequestClose = true
        anchors.endTransition()
        onClose()
    }
}
