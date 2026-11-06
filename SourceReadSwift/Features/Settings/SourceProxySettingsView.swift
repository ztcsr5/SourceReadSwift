import SwiftUI

struct SourceProxySettingsView: View {
    @ObservedObject private var proxyManager = SourceProxyManager.shared
    @State private var isEnabled = false
    @State private var host = ""
    @State private var port = ""
    @State private var protocolKind = SourceProxyConfiguration.ProtocolKind.http
    @State private var validationMessage: String?
    @State private var testTask: Task<Void, Never>?

    private var hasChanges: Bool {
        let saved = proxyManager.configuration
        return saved.isEnabled != isEnabled ||
            (isEnabled && (saved.host != host || String(saved.port) != port || saved.protocolKind != protocolKind))
    }

    private var isTesting: Bool { testTask != nil }
    @State private var testResult: String?
    @State private var showingTestResult = false
    private enum Field: Hashable { case host, port }
    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            Section {
                Toggle("启用书源网络代理", isOn: $isEnabled)
            } footer: {
                Text("保存后，使用书源网络会话的新请求会通过此代理。部分书源脚本使用独立网络通道。")
            }
            .listRowBackground(AppThemeRowSurface())

            if isEnabled {
                Section("代理协议与配置") {
                    BrandSegmentedControl("代理类型", selection: $protocolKind, options:
                            [(.http, "HTTP / HTTPS"), (.socks5, "SOCKS5")])

                    HStack {
                        Text("代理主机")
                        Spacer()
                        TextField("127.0.0.1", text: $host)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focusedField, equals: .host)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .port }
                    }

                    HStack {
                        Text("代理端口")
                        Spacer()
                        TextField("7890", text: $port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .port)
                    }
                }
                .listRowBackground(AppThemeRowSurface())
            }

            Section {
                Button("保存代理设置", action: saveSettings)
                    .disabled(!hasChanges)
                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            } footer: {
                Text("保存后才会应用到新请求。")
            }
            .listRowBackground(AppThemeRowSurface())

            if isEnabled {
                Section("代理连通性测试") {
                    Button {
                        focusedField = nil
                        testProxyConnection()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text(isTesting ? "正在测试连通性..." : "测试代理连接")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .disabled(isTesting || hasChanges)
                    if hasChanges {
                        Text("保存配置后再测试连接。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(AppThemeRowSurface())

                Section("常见代理软件端口参考") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Clash / Mihomo 默认端口: 7890 (混合) / 7891")
                        Text("• Shadowrocket 默认代理端口: 1082 (HTTP)")
                        Text("• Surge 默认代理端口: 6152 (HTTP) / 6153 (SOCKS5)")
                        Text("• 局域网分流请将代理主机设为宿主机 IP（如 192.168.x.x）")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .listRowBackground(AppThemeRowSurface())
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
        }
        .onAppear(perform: loadDraft)
        .onDisappear {
            testTask?.cancel()
            testTask = nil
        }
        .onChange(of: isEnabled) { enabled in
            validationMessage = nil
            if !enabled { focusedField = nil }
        }
        .pageBackground()
        .navigationTitle("书源网络代理")
        .navigationBarTitleDisplayMode(.inline)
        .alert("代理测试结果", isPresented: $showingTestResult) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(testResult ?? "")
        }
    }

    private func loadDraft() {
        let saved = proxyManager.configuration
        isEnabled = saved.isEnabled
        host = saved.host
        port = String(saved.port)
        protocolKind = saved.protocolKind
    }

    private func saveSettings() {
        focusedField = nil
        do {
            try proxyManager.save(isEnabled: isEnabled, host: host, port: port, protocolKind: protocolKind)
            testTask?.cancel()
            testTask = nil
            validationMessage = nil
            loadDraft()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func testProxyConnection() {
        guard testTask == nil, !hasChanges, let url = URL(string: "https://www.baidu.com") else { return }
        let proxy = proxyManager.configuration
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        testTask = Task { @MainActor in
            let start = ProcessInfo.processInfo.systemUptime
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 8
            config.connectionProxyDictionary = proxy.connectionProxyDictionary
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }

            let message: String
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                let (_, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let elapsed = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
                message = (200...399).contains(status) ? "连接成功，耗时 \(elapsed) 毫秒（HTTP \(status)）。"
                    : "测试站点响应异常（HTTP \(status)）。"
            } catch {
                message = "连接失败：\(error.localizedDescription)\n检查代理是否正在运行并允许局域网连接。"
            }
            guard !Task.isCancelled else { return }
            testTask = nil
            testResult = message
            showingTestResult = true
        }
    }
}
