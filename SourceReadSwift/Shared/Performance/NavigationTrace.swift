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
    @Published private(set) var stallCount = 0
    @Published private(set) var maxStallMS = 0.0

    private let storageKey = "settings.navigationTrace"
    private let limit = 4000
    private var origin = CACurrentMediaTime()
    private var timer: DispatchSourceTimer?
    private var lastTick = CACurrentMediaTime()
    /// 最近几条事件，用来给停顿附上下文：卡之前最后在干什么。
    private var breadcrumbs: [String] = []

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
        breadcrumbs.removeAll(keepingCapacity: true)
        stallCount = 0
        maxStallMS = 0
        lastNavHidden = nil
        lastTabHidden = nil

        // 50 ms 一跳的主线程心跳：迟到超过 80 ms 说明主线程被占住。
        // 阈值取 80 而非 100，是因为 80ms 已经足以让一次转场掉帧。
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 0.05, repeating: 0.05, leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in
            guard let self, self.isEnabled else { return }
            let now = CACurrentMediaTime()
            let gap = now - self.lastTick
            let blocked = (gap - 0.05) * 1000
            if blocked >= 80 {
                self.stallCount += 1
                if blocked > self.maxStallMS { self.maxStallMS = blocked }
                let since = self.breadcrumbs.suffix(4).joined(separator: " › ")
                self.mark("STALL", String(format: "主线程停顿 %.0f ms", blocked)
                          + (since.isEmpty ? "" : "  ← " + since))
            }
            self.sampleChrome()
            self.lastTick = now
        }
        source.resume()
        timer = source
        mark("trace", "开始记录 " + deviceSummary)
    }

    // MARK: - 真实 chrome 状态采样
    //
    // 光看 SwiftUI 的调用顺序不够：要回答「栏到底在哪一刻真的变可见」，
    // 只能直接读 UIKit 的 `isNavigationBarHidden` / `tabBar.isHidden`，
    // 把变化时刻和时间线对齐。这样「提前浮出」就有了毫秒级证据。

    private var lastNavHidden: Bool?
    private var lastTabHidden: Bool?

    private func sampleChrome() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              let root = window.rootViewController else { return }

        if let nav = Self.firstNavigationController(in: root) {
            let hidden = nav.isNavigationBarHidden || nav.navigationBar.isHidden
            if hidden != lastNavHidden {
                lastNavHidden = hidden
                let depth = nav.viewControllers.count
                mark("NAV", "navigationBar \(hidden ? "隐藏" : "显示") 栈深=\(depth)")
            }
        }
        if let tabs = Self.firstTabBarController(in: root) {
            let hidden = tabs.tabBar.isHidden
            if hidden != lastTabHidden {
                lastTabHidden = hidden
                mark("TAB", "tabBar \(hidden ? "隐藏" : "显示")")
            }
        }
    }

    private static func firstNavigationController(in controller: UIViewController) -> UINavigationController? {
        if let nav = controller as? UINavigationController { return nav }
        for child in controller.children {
            if let found = firstNavigationController(in: child) { return found }
        }
        return controller.presentedViewController.flatMap { firstNavigationController(in: $0) }
    }

    private static func firstTabBarController(in controller: UIViewController) -> UITabBarController? {
        if let tabs = controller as? UITabBarController { return tabs }
        for child in controller.children {
            if let found = firstTabBarController(in: child) { return found }
        }
        return controller.presentedViewController.flatMap { firstTabBarController(in: $0) }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        breadcrumbs.removeAll(keepingCapacity: true)
        stallCount = 0
        maxStallMS = 0
        lastNavHidden = nil
        lastTabHidden = nil
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
        breadcrumbs.append(category + ":" + text)
        if breadcrumbs.count > 12 { breadcrumbs.removeFirst(breadcrumbs.count - 12) }
    }

    /// 只进入面包屑，不写时间线。用于高频事件（store 通知、滚动），
    /// 避免刷屏，但仍然能出现在停顿的上下文里。
    func breadcrumb(_ category: String, _ text: String) {
        guard isEnabled else { return }
        breadcrumbs.append(category + ":" + text)
        if breadcrumbs.count > 12 { breadcrumbs.removeFirst(breadcrumbs.count - 12) }
    }

    var deviceSummary: String {
        let info = Bundle.main.infoDictionary
        let build = (info?["CFBundleVersion"] as? String) ?? "-"
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "-"
        return "\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion) · 纸间 \(version)(\(build))"
    }

    var summary: String {
        String(format: "事件 %d 条 · 停顿 %d 次 · 最长 %.0f ms", entries.count, stallCount, maxStallMS)
    }

    var snapshot: String {
        summary + "\n" + deviceSummary + "\n\n" + entries.map(\.line).joined(separator: "\n")
    }

    func snapshot(categories: Set<String>) -> String {
        let filtered = categories.isEmpty ? entries : entries.filter { categories.contains($0.category) }
        return summary + "\n" + deviceSummary + "\n\n" + filtered.map(\.line).joined(separator: "\n")
    }

    /// 时间线里出现过的分类，用于筛选条。
    var categories: [String] {
        var seen: [String] = []
        for entry in entries where !seen.contains(entry.category) { seen.append(entry.category) }
        return seen
    }
}

/// 设置 → 诊断 → 侧滑返回诊断。记录、筛选、复制，全在 App 内闭环。
struct NavigationTraceView: View {
    @ObservedObject private var trace = NavigationTrace.shared
    @State private var copied = false
    @State private var filter: String?

    private var enabledBinding: Binding<Bool> {
        Binding(get: { trace.isEnabled }, set: { trace.setEnabled($0) })
    }

    private var visible: [NavigationTrace.Entry] {
        let all = trace.entries
        guard let filter else { return Array(all.suffix(600)) }
        if filter == "STALL" { return Array(all.filter { $0.category == "STALL" }.suffix(600)) }
        return Array(all.filter { $0.category == filter }.suffix(600))
    }

    var body: some View {
        List {
            Section {
                Toggle("记录侧滑返回时间线", isOn: enabledBinding)
                Text(trace.summary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    UIPasteboard.general.string = trace.snapshot(categories: filter.map { [$0] } ?? [])
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制全部记录", systemImage: "doc.on.doc")
                }
                .disabled(trace.entries.isEmpty)
                Button("清空", role: .destructive) { trace.clear() }
            } footer: {
                Text("记录：pop 转场（是否交互/取消）、tab 栏所有权、书架投影、阅读器与详情进出、tab 切换、store 通知、主线程 ≥80ms 停顿（附前 4 条上下文）。复现一次问题后回来复制全文。")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("全部", tag: nil)
                        chip("只有停顿", tag: "STALL")
                        ForEach(trace.categories.filter { $0 != "STALL" }, id: \.self) { category in
                            chip(category, tag: category)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("最近 600 条") {
                if visible.isEmpty {
                    Text("暂无记录").foregroundStyle(.secondary)
                } else {
                    ForEach(visible) { entry in
                        Text(entry.line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(entry.category == "STALL" ? Color.orange : Color.primary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("侧滑返回诊断")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if trace.isEnabled { trace.start() } }
    }

    private func chip(_ title: String, tag: String?) -> some View {
        let selected = filter == tag
        return Button {
            filter = tag
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
