import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Exports the chosen image. UIKit and the container's shortcut are independent.
struct HomeScreenIconExportView: View {
    @State private var option: AppIconOption
    @State private var document: HomeScreenIconDocument?
    @State private var filename = "纸间"
    @State private var isExporting = false
    @State private var exportMessage: String?
    @ObservedObject private var personalMark = PersonalBrandMarkStore.shared
    private static let guideURL = URL(string: "https://livecontainer.github.io/zh-CN/docs/guides/add-to-home-screen")!

    init(initialOption: AppIconOption) {
        _option = State(initialValue: initialOption)
    }

    var body: some View {
        Form {
            Section("导出图标图片") {
                HStack(spacing: 16) {
                    Image(option.brandMarkAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    Picker("图标样式", selection: $option) {
                        ForEach(AppIconOption.allCases) { icon in
                            Text(icon.title).tag(icon)
                        }
                    }
                    .accessibilityIdentifier("appearance.shortcutIconChoice")
                }
                Button {
                    export(UIImage(named: option.brandMarkAssetName), identifier: option.rawValue)
                } label: {
                    Label("导出所选图标", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("appearance.exportShortcutIcon")
                if let image = personalMark.image {
                    Button("导出相册徽标") {
                        export(image, identifier: "个人徽标")
                    }
                }
                if let exportMessage {
                    Text(exportMessage).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("appearance.shortcutExportStatus")
                }
            }
            .listRowBackground(AppThemeRowSurface())

            Section("添加到 iPhone 主屏幕") {
                instruction(1, "在 LiveContainer 中长按「纸间」，从「添加到主屏幕」复制启动 URL。")
                instruction(2, "在快捷指令添加 LiveContainer 的「Launch App」动作，粘贴启动 URL。找不到该动作时改用「打开 URL」。")
                instruction(3, "在快捷指令选择「添加到主屏幕」，点图标选刚导出的文件。也可直接选自己的照片。")
                Link(destination: Self.guideURL) {
                    Label("查看 LiveContainer 图文指引", systemImage: "arrow.up.right")
                }
            }
            .listRowBackground(AppThemeRowSurface())
        }
        .pageBackground()
        .navigationTitle("主屏幕快捷入口")
        .navigationBarTitleDisplayMode(.inline)
        .task { await personalMark.loadIfNeeded() }
        .fileExporter(isPresented: $isExporting, document: document, contentType: .png, defaultFilename: filename) { result in
            switch result {
            case .success:
                exportMessage = "图标文件已保存。请在快捷指令中选用该图片，桌面入口不会自动改变。"
            case .failure(let error):
                exportMessage = "文件未保存：\(error.localizedDescription)"
            }
        }
    }

    private func instruction(_ number: Int, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number.formatted())
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.accent)
            Text(title).font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private func export(_ image: UIImage?, identifier: String) {
        guard let image, let payload = image.pngData() else {
            exportMessage = "无法生成 PNG，请选另一款图标。"
            return
        }
        exportMessage = nil
        filename = "纸间-\(identifier)"
        document = HomeScreenIconDocument(png: payload)
        isExporting = true
    }
}

struct HomeScreenIconDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let png: Data

    init(png: Data) { self.png = png }

    init(configuration: ReadConfiguration) throws {
        guard let png = configuration.file.regularFileContents, !png.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.png = png
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: png)
    }
}
