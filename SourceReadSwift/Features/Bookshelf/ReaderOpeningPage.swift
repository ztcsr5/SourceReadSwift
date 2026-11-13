import SwiftUI

private struct ReaderBookReturnKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ReaderOpeningManagedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var readerUsesBookReturn: Bool {
        get { self[ReaderBookReturnKey.self] }
        set { self[ReaderBookReturnKey.self] = newValue }
    }

    var readerOpeningManaged: Bool {
        get { self[ReaderOpeningManagedKey.self] }
        set { self[ReaderOpeningManagedKey.self] = newValue }
    }
}

/// 覆盖层/原生路由读取该信号以确认正文就绪，不再渲染任何正文前介绍遮罩或「纸间·阅读」过渡页。
struct ReaderOpeningReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func readerOpeningContentReady(_ ready: Bool = true) -> some View {
        modifier(ReaderOpeningReadiness(ready: ready))
    }
}

private struct ReaderOpeningReadiness: ViewModifier {
    let ready: Bool
    @Environment(\.nativeReaderSession) private var session

    func body(content: Content) -> some View {
        content.preference(key: ReaderOpeningReadyKey.self, value: ready)
            .onAppear { if ready { session?.recordReadyReceipt() } }
            .onChange(of: ready) { if $0 { session?.recordReadyReceipt() } }
    }
}
