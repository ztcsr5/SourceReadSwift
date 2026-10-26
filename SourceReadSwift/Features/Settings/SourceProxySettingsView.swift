import SwiftUI

struct SourceProxySettingsView: View {
    @ObservedObject private var proxyManager = SourceProxyManager.shared
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var showingTestResult = false

    var body: some View {
        Form {
            Section {
                Toggle("启用书源网络代理", isOn: $proxyManager.isEnabled)
            } footer: {
                Text("开启后，所有书源的网络请求（搜索、目录、正文加载、分类发现等）都将通过指定的本地或局域网代理服务器转发。")
            }

            if proxyManager.isEnabled {
                Section("代理协议与配置") {
                    Picker("代理类型", selection: $proxyManager.proxyType) {
                        Text("HTTP / HTTPS").tag("http")
                        Text("SOCKS5").tag("socks5")
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("代理主机")
                        Spacer()
                        TextField("127.0.0.1", text: $proxyManager.host)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.numbersAndPunctuation)
                    }

                    HStack {
                        Text("代理端口")
                        Spacer()
                        TextField("7890", value: $proxyManager.port, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("代理连通性测试") {
                    Button {
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
                    .disabled(isTesting)
                }

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
            }
        }
        .navigationTitle("书源网络代理")
        .navigationBarTitleDisplayMode(.inline)
        .alert("代理测试结果", isPresented: $showingTestResult) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(testResult ?? "")
        }
    }

    private func testProxyConnection() {
        isTesting = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            let start = Date()
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            proxyManager.applyProxy(to: config)
            let session = URLSession(configuration: config)

            guard let url = URL(string: "https://www.baidu.com") else {
                await MainActor.run {
                    isTesting = false
                    testResult = "测试 URL 非法"
                    showingTestResult = true
                }
                return
            }

            do {
                let (_, response) = try await session.data(from: url)
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run {
                    isTesting = false
                    if (200...399).contains(statusCode) {
                        testResult = "连接成功！耗时: \(elapsed)ms (状态码: \(statusCode))"
                    } else {
                        testResult = "代理响应异常，状态码: \(statusCode)"
                    }
                    showingTestResult = true
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = "连接失败: \(error.localizedDescription)\n请检查代理客户端是否正常运行并开启了允许局域网连接。"
                    showingTestResult = true
                }
            }
        }
    }
}
