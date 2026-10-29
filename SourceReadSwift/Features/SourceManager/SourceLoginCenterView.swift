import SwiftUI

/// Unified source-login console.
///
/// Before this screen the only way to authenticate a source was to find its
/// row inside the source manager and long-press it. Readers who hit a 401 in
/// the middle of a book had no path back to the right source, and the settings
/// screen only showed cookies that already existed. This page lists every
/// source that declares (or can fall back to) a login target, shows whether a
/// cookie session already exists, and lets the reader sign in or out in place.
struct SourceLoginCenterView: View {
    let sources: [BookSource]
    let cookieStore: SourceCookieStore
    var engine: SourceEngine?

    @State private var keyword = ""
    @State private var loggedInHosts: Set<String> = []
    @State private var cookieCountsByHost: [String: Int] = [:]
    @State private var loginTarget: BookSource?
    @State private var pendingSignOutHost: String?
    @State private var signOutHostLabel = ""

    private struct Entry: Identifiable {
        let source: BookSource
        let host: String
        let usedHomePageFallback: Bool
        var id: String { source.bookSourceUrl }
        var hasConfiguredForm: Bool {
            !(source.loginUi ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var entries: [Entry] {
        sources.compactMap { source in
            guard let target = SourceLoginURLResolver.resolve(source: source), let host = target.url.host?.lowercased(), !host.isEmpty else { return nil }
            return Entry(source: source, host: host, usedHomePageFallback: target.usedBookSourceFallback)
        }
    }

    private var filteredEntries: [Entry] {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.source.bookSourceName.localizedCaseInsensitiveContains(query)
                || entry.source.bookSourceUrl.localizedCaseInsensitiveContains(query)
                || (entry.source.bookSourceGroup ?? "").localizedCaseInsensitiveContains(query)
                || entry.host.localizedCaseInsensitiveContains(query)
        }
    }

    private var signedInEntries: [Entry] {
        filteredEntries.filter { loggedInHosts.contains($0.host) }
    }

    private var signedOutEntries: [Entry] {
        filteredEntries.filter { !loggedInHosts.contains($0.host) }
    }

    var body: some View {
        List {
            summarySection
            if filteredEntries.isEmpty {
                emptySection
            } else {
                if !signedInEntries.isEmpty {
                    Section {
                        ForEach(signedInEntries) { entry in
                            row(entry, signedIn: true)
                        }
                    } header: {
                        Text("已登录 \(signedInEntries.count)")
                    } footer: {
                        Text("这些站点已保存 Cookie 会话，请求书源时会自动携带。")
                    }
                }
                if !signedOutEntries.isEmpty {
                    Section {
                        ForEach(signedOutEntries) { entry in
                            row(entry, signedIn: false)
                        }
                    } header: {
                        Text("未登录 \(signedOutEntries.count)")
                    } footer: {
                        Text("带「主页登录」标记的源没有写 loginUrl，会在书源主页打开登录页；登录成功后返回即可。")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $keyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书源 / 域名")
        .navigationTitle("书源登录中心")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshSessions() }
        .sheet(item: $loginTarget, onDismiss: {
            Task { await refreshSessions() }
        }) { source in
            SourceLoginView(source: source, cookieStore: cookieStore, engine: engine)
        }
        .confirmationDialog(
            "退出登录 \(signOutHostLabel)？",
            isPresented: Binding(
                get: { pendingSignOutHost != nil },
                set: { if !$0 { pendingSignOutHost = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("清除该站点 Cookie", role: .destructive) {
                if let host = pendingSignOutHost {
                    Task {
                        await cookieStore.clearCookies(for: host)
                        await refreshSessions()
                    }
                }
                pendingSignOutHost = nil
            }
            Button("取消", role: .cancel) { pendingSignOutHost = nil }
        } message: {
            Text("清除后，该站点需要重新登录才能访问需要账号的章节。")
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 14) {
                statBlock(value: "\(entries.count)", label: "可登录源", tint: AppTheme.accent)
                Divider().frame(height: 30)
                statBlock(value: "\(entries.filter { loggedInHosts.contains($0.host) }.count)", label: "已登录", tint: .green)
                Divider().frame(height: 30)
                statBlock(value: "\(cookieCountsByHost.values.reduce(0, +))", label: "Cookie 数", tint: .secondary)
            }
            .padding(.vertical, 4)

            if !loggedInHosts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("已有 \(loggedInHosts.count) 个站点保持登录状态")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statBlock(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text(keyword.isEmpty ? "没有可登录的书源" : "没有匹配的书源")
                    .font(.subheadline)
                Text("书源里没有配置 loginUrl，也没有可回退的站点主页。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func row(_ entry: Entry, signedIn: Bool) -> some View {
        Button {
            loginTarget = entry.source
        } label: {
            HStack(spacing: 12) {
                Image(systemName: signedIn ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(signedIn ? Color.green : Color.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.source.bookSourceName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(entry.host)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if entry.hasConfiguredForm {
                            tag("表单登录", color: .blue)
                        } else if entry.usedHomePageFallback {
                            tag("主页登录", color: .orange)
                        }
                    }
                }
                Spacer(minLength: 6)
                if signedIn {
                    Text("已登录")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("去登录")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if signedIn {
                Button(role: .destructive) {
                    signOutHostLabel = entry.host
                    pendingSignOutHost = entry.host
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .contextMenu {
            Button {
                loginTarget = entry.source
            } label: {
                Label(signedIn ? "重新登录" : "登录", systemImage: "key.fill")
            }
            if signedIn {
                Button(role: .destructive) {
                    signOutHostLabel = entry.host
                    pendingSignOutHost = entry.host
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func refreshSessions() async {
        let hosts = await cookieStore.hostsWithCookies()
        var normalized: Set<String> = []
        var counts: [String: Int] = [:]
        for host in hosts {
            let clean = host.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
            guard !clean.isEmpty else { continue }
            normalized.insert(clean)
            if let url = URL(string: "https://\(clean)") {
                counts[clean] = await cookieStore.cookies(for: url).count
            }
        }
        await MainActor.run {
            loggedInHosts = normalized
            cookieCountsByHost = counts
        }
    }
}