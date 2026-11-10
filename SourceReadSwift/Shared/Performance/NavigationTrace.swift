import Foundation
import Combine
import SwiftUI
import UIKit
import QuartzCore

/// 侧滑返回专用时间线。
///
/// 这台开发机没有 macOS / Xcode，`os.Logger` + Console 这条路是断的，
/// 所以关键路径必须自己记录、自己展示、自己复制出来。所有事件共用一个
/// 起点（开启记录那一刻），按相对秒数排序，能直接读出「谁先谁后、谁卡了多久」。
///
/// 只用主线程写入：所有埋点都发生在 UI 生命周期回调里，不需要加锁。
final class NavigationTrace: ObservableObject {
    static let shared = NavigationTrace()

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let offset: Double
        let category: String
        let text: String

        var line: String {
            String(format: "+%8.3fs  ", offset) + category.padding(toLength: 7, withPad: " ", startingAt: 0) + text
        }
    }

    @Published private(set) var entries: [Entry] = []

    private let storageKey = "settings.navigationTrace"
    private let limit = 4000
    private var origin = CACurrentMediaTime()
    private var timer: DispatchSourceTimer?
    private var lastTick = CACurrentMediaTime()

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: storageKey)
        if enabled { start() } else { stop() }
    }

    func start() {
        guard timer == nil else { return }
        origin = CACurrentMediaTime()
        lastTick = origin
        entries.removeAll(keepingCapacity: true)

        // 50 ms 一跳的主线程心跳：迟到超过 100 ms 说明主线程被占住，
        // 这就是「主页要等一会才能动」的直接证据。
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 0.05, repeating: 0.05, leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in
            guard let self, self.isEnabled else { return }
            let now = CACurrentMediaTime()
            let gap = now - self.lastTick
            if gap > 0.10 {
                self.mark("stall", String(format: "主线程停顿 %.0f ms", (gap - 0.05) * 1000))
            }
            self.lastTick = now
        }
        source.resume()
        timer = source
        mark("trace", "开始记录")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        origin = CACurrentMediaTime()
        lastTick = origin
    }

    /// 关闭记录时直接返回，埋点保持零成本。
    func mark(_ category: String, _ text: String) {
        guard isEnabled else { return }
        let offset = CACurrentMediaTime() - origin
        entries.append(Entry(offset: offset, category: category, text: text))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    var snapshot: String {
        entries.map(\.line).joined(separator: "\n")
    }
}

/// 设置 → 诊断 → 侧滑返回诊断。记录、查看、复制，全在 App 内闭环。
struct NavigationTraceView: View {
    @ObservedObject private var trace = NavigationTrace.shared
    @State private var copied = false

    private var enabledBinding: Binding<Bool> {
        Binding(get: { trace.isEnabled }, set: { trace.setEnabled($0) })
    }

    var body: some View {
        List {
            Section {
                Toggle("记录侧滑返回时间线", isOn: enabledBinding)
                Button {
                    UIPasteboard.general.string = trace.snapshot
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制全部记录", systemImage: "doc.on.doc")
                }
                .disabled(trace.entries.isEmpty)
                Button("清空", role: .destructive) { trace.clear() }
            } footer: {
                Text("开启后按相对秒数记录：pop 转场（是否交互、是否取消）、tab 栏所有权变化、书架投影是否重建、详情/阅读器出现与消失，以及主线程超过 100 ms 的停顿。复现一次问题后回到这里复制全文。")
            }

            Section("时间线（最近 400 条）") {
                if trace.entries.isEmpty {
                    Text("暂无记录").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(trace.entries.suffix(400))) { entry in
                        Text(entry.line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("侧滑返回诊断")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if trace.isEnabled { trace.start() } }
    }
}
