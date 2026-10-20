import SwiftUI
import UIKit

/// Sheet presented when a Legado source calls `java.getVerificationCode`.
/// The image is fetched with the source-scoped cookie header because most
/// captcha endpoints bind the challenge to the current session.
struct VerificationCodeSheet: View {
    let request: VerificationCodeRequest
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var code = ""
    @State private var reloadToken = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VerificationCodeImage(
                        urlString: request.imageURL,
                        cookieHeader: request.cookieHeader,
                        reloadToken: reloadToken
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("验证码")
                } footer: {
                    Text("图片过期或看不清时点右上角刷新；验证码仅保存在当前书源会话。")
                }

                Section {
                    TextField("输入图片中的字符", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($isFocused)
                        .onSubmit(submit)
                } footer: {
                    Text("来源：\(request.sourceName) · 阶段：\(request.stage)\n验证码仅保存在当前书源会话，用于本次请求重试。")
                }
            }
            .navigationTitle("需要验证码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        reloadToken += 1
                    } label: {
                        Label("刷新验证码", systemImage: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新验证码")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交", action: submit)
                        .disabled(trimmedCode.isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .interactiveDismissDisabled()
    }

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedCode.isEmpty else { return }
        onSubmit(trimmedCode)
    }
}

private struct VerificationCodeImage: View {
    let urlString: String
    let cookieHeader: String
    let reloadToken: Int

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .accessibilityLabel("验证码图片")
            } else if failed {
                Label("验证码图片加载失败，请刷新或直接输入", systemImage: "photo.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: "\(urlString)#\(reloadToken)") { await load() }
    }

    private func load() async {
        image = nil
        failed = false

        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            failed = true
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // Captcha endpoints rotate the image behind a stable URL; bypassing the
        // local cache is required for the refresh button to show a new code.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data) else {
                failed = true
                return
            }
            image = decoded
        } catch {
            failed = true
        }
    }
}
