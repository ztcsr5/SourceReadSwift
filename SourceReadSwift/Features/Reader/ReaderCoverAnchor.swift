import SwiftUI
import UIKit

/// 记录每一本书封面在**窗口坐标系**里的真实矩形。
///
/// 坐标空间统一用 `.global`：它是以窗口为基准的，滚动容器、Safe Area、
/// GeometryReader 嵌套都不会改变它的含义，覆盖层读到的值与采集点一致。
/// 这是唯一被使用的坐标系，别处不要混用 `.local` / `.named`。
///
/// 只有 `hiddenBookID` 是 `@Published`：进入/退出各改一次，书架重算一次。
/// 矩形本身刻意不是 `@Published`，滚动时每帧都会更新，发布它等于每帧全页重排。
@MainActor
final class ReaderCoverAnchorStore: ObservableObject {
    static let shared = ReaderCoverAnchorStore()

    /// 过渡期间需要隐藏源封面的书。nil 表示没有进行中的过渡。
    @Published private(set) var hiddenBookID: String?

    private var rects: [String: CGRect] = [:]

    func setRect(_ rect: CGRect, for bookID: String) {
        // 忽略尚未完成布局的无效矩形，避免把 0 尺寸当成封面位置。
        guard rect.width > 1, rect.height > 1 else { return }
        rects[bookID] = rect
    }

    func rect(for bookID: String) -> CGRect? { rects[bookID] }

    /// 开始过渡：隐藏源封面，但保留其布局占位，书架不跳动。
    func beginTransition(bookID: String) {
        if hiddenBookID != bookID { hiddenBookID = bookID }
    }

    /// 过渡结束（进入成功或取消）：恢复源封面。
    func endTransition() {
        if hiddenBookID != nil { hiddenBookID = nil }
    }
}

private struct ReaderCoverAnchorModifier: ViewModifier {
    let bookID: String
    @ObservedObject private var store = ReaderCoverAnchorStore.shared

    func body(content: Content) -> some View {
        content
            // 隐藏用 opacity 而不是移除：布局尺寸不变，书架不会因为起点消失而跳动。
            .opacity(store.hiddenBookID == bookID ? 0 : 1)
            .background(
                GeometryReader { proxy in
                    let rect = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { store.setRect(rect, for: bookID) }
                        .onChange(of: rect) { newValue in store.setRect(newValue, for: bookID) }
                }
            )
    }
}

extension View {
    /// 把这棵视图登记为某本书的封面来源。滚动时会持续更新真实位置。
    func readerCoverAnchor(_ bookID: String) -> some View {
        modifier(ReaderCoverAnchorModifier(bookID: bookID))
    }
}

// MARK: - 覆盖层标记

private struct ReaderOverlayPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 阅读器是否以覆盖层呈现。旧 NavigationStack 路径为 false。
    /// 覆盖层路径不需要隐藏/恢复 tab chrome，用这个标记隔离两套生命周期。
    var readerPresentedAsOverlay: Bool {
        get { self[ReaderOverlayPresentationKey.self] }
        set { self[ReaderOverlayPresentationKey.self] = newValue }
    }
}

// MARK: - 正文就绪收集

/// 收集阅读器内部发出的正文就绪信号。
///
/// `ReaderView` / `ComicReaderView` 与错误页都会发 `.readerOpeningContentReady(...)`，
/// 以前由 `ReaderOpeningPresentation` 消费；覆盖层路径没有那一层，必须在这里接住，
/// 否则"正文是否真的可就位"对覆盖层完全不可见。
private struct ReaderReadyCollector: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onPreferenceChange(ReaderOpeningReadyKey.self) { ready in onChange(ready) }
    }
}

extension View {
    func readerReadySignal(_ onChange: @escaping (Bool) -> Void) -> some View {
        modifier(ReaderReadyCollector(onChange: onChange))
    }
}
