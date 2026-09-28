import SwiftUI

struct CookieManagerView: View {
    let cookieStore: SourceCookieStore
    @State private var hosts: [String] = []
    @State private var cookiesByHost: [String: [HTTPCookie]] = [:]
    @State private var totalCount: Int = 0
    @State private var showClearAllConfirmation = false
    @State private var expandedHosts: Set<String> = []

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("持久化 Cookie 会话")
                            .font(.headline)
                        Text("书源登录凭证与防刷校验 Token 已安全持久化至本地存储")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(totalCount) 个")
                        .font(.subheadline.bold())
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(.vertical, 4)
            }

            if hosts.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("暂无持久化 Cookie 会话")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("当书源需要登录或通过 WebKit 验证后，其会话凭证将自动保存并在后续请求中自动携带。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                Section("站点列表 (\(hosts.count))") {
                    ForEach(hosts, id: \.self) { host in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedHosts.contains(host) },
                                set: { if $0 { expandedHosts.insert(host) } else { expandedHosts.remove(host) } }
                            )
                        ) {
                            if let cookies = cookiesByHost[host] {
                                ForEach(cookies, id: \.name) { cookie in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(cookie.name)
                                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                            Spacer()
                                            if cookie.isSecure {
                                                Image(systemName: "lock.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.green)
                                            }
                                            if cookie.isHTTPOnly {
                                                Text("HTTPOnly")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.15))
                                                    .cornerRadius(4)
                                            }
                                        }
                                        Text(cookie.value)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        if let expires = cookie.expiresDate {
                                            Text("有效期至: \(expires.formatted(date: .numeric, time: .shortened))")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundStyle(Color.accentColor)
                                Text(host)
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                                Text("\((cookiesByHost[host] ?? []).count) 项")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteHostCookies(host)
                            } label: {
                                Label("清除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Cookie 会话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !hosts.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showClearAllConfirmation = true
                    } label: {
                        Text("清空全部")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .confirmationDialog(
            "确认清除全部持久化 Cookie？",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除全部会话", role: .destructive) {
                clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清除后需要登录或防盗链校验的书源可能需要重新登录。")
        }
        .task {
            await reloadData()
        }
    }

    private func reloadData() async {
        let cookieList = await cookieStore.allCookies()
        let count = await cookieStore.cookieCount()
        var grouped: [String: [HTTPCookie]] = [:]
        for c in cookieList {
            let host = c.domain.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
            grouped[host, default: []].append(c)
        }
        let sortedHosts = grouped.keys.sorted()

        await MainActor.run {
            self.totalCount = count
            self.cookiesByHost = grouped
            self.hosts = sortedHosts
        }
    }

    private func deleteHostCookies(_ host: String) {
        HapticFeedback.medium()
        Task {
            await cookieStore.clearCookies(for: host)
            await reloadData()
        }
    }

    private func clearAll() {
        HapticFeedback.error()
        Task {
            await cookieStore.clearAllCookies()
            await reloadData()
        }
    }
}
