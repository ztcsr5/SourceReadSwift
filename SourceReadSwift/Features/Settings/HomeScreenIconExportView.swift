import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Exports the chosen image. UIKit and the container's shortcut are independent.
struct HomeScreenIconExportView: View {
    private enum Artwork: Hashable {
        case builtIn(AppIconOption), photo
    }

    @State private var artwork: Artwork
    @State private var document: HomeScreenIconDocument?
    @State private var filename = "纸间"
    @State private var isExporting = false
    @State private var exportMessage: String?
    @State private var launchLink = ""
    @State private var launchMessage: String?
    @Environment(\.openURL) private var openURL
    @AppStorage(PersonalBrandMarkStore.frameKey) private var photoFrameRaw = PersonalBrandMarkStore.Frame.full.rawValue
    @ObservedObject private var personalMark = PersonalBrandMarkStore.shared
    private let initialOption: AppIconOption
    private static let guideURL = URL(string: "https://livecontainer.github.io/zh-CN/docs/guides/add-to-home-screen")!

    init(initialOption: AppIconOption, prefersPersonalMark: Bool = false) {
        self.initialOption = initialOption
        _artwork = State(initialValue: prefersPersonalMark ? .photo : .builtIn(initialOption))
    }

    var body: some View {
        Form {
            Section("导出图标图片") {
                HStack(spacing: 16) {
                    iconPreview
                    Picker("图标样式", selection: $artwork) {
                        ForEach(AppIconOption.allCases) { icon in
                            Text(icon.title).tag(Artwork.builtIn(icon))
                        }
                        if personalMark.image != nil { Text("相册自定义").tag(Artwork.photo) }
                    }
                    .accessibilityIdentifier("appearance.shortcutIconChoice")
                }
                Button {
                    exportSelectedArtwork()
                } label: {
                    Label("导出所选图标", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("appearance.exportShortcutIcon")
                if let exportMessage {
                    Text(exportMessage).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("appearance.shortcutExportStatus")
                }
            }
            .listRowBackground(AppThemeRowSurface())

            Section("LiveContainer · 先验证能启动") {
                instruction(1, "在 LiveContainer 里长按纸间；有多个容器时先选对容器，再从「添加到主屏幕」复制启动 URL。")
                TextField("粘贴 LiveContainer 启动 URL", text: $launchLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("appearance.liveContainerLaunchURL")
                Button("试开启动链接") { testLaunchLink() }
                    .disabled(launchLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let launchMessage {
                    Text(launchMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("appearance.liveContainerLaunchResult")
                }
                instruction(2, "在快捷指令用 LiveContainer 的「Launch App」动作。找不到时用「打开 URL」，粘贴同一个地址。")
                Link(destination: Self.guideURL) {
                    Label("查看 LiveContainer 图文指引", systemImage: "arrow.up.right")
                }
            }
            .listRowBackground(AppThemeRowSurface())

            Section("把同款图放在主屏幕") {
                Text("独立安装的纸间用快捷指令「打开 App」选纸间；LiveContainer 用上方已经测试过的链接。")
                Text("在快捷指令点「添加到主屏幕」→「选取文件」，选择刚导出的 PNG。旧快捷指令不会自动换图。")
            }
            .font(.subheadline)
            .listRowBackground(AppThemeRowSurface())
        }
        .pageBackground()
        .navigationTitle("主屏幕快捷入口")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await personalMark.loadIfNeeded()
            if artwork == .photo, personalMark.image == nil { artwork = .builtIn(initialOption) }
        }
        .fileExporter(isPresented: $isExporting, document: document, contentType: .png, defaultFilename: filename) { result in
            switch result {
            case .success:
                exportMessage = "图标文件已保存。请在快捷指令中选用该图片，桌面入口不会自动改变。"
            case .failure(let error):
                exportMessage = "文件未保存：\(error.localizedDescription)"
            }
        }
    }

    private var photoFrame: PersonalBrandMarkStore.Frame {
        PersonalBrandMarkStore.Frame(rawValue: photoFrameRaw) ?? .full
    }

    private var iconPreview: some View {
        let size: CGFloat = 64
        let image: Image
        let inset: CGFloat
        switch artwork {
        case .builtIn(let option):
            image = Image(option.brandMarkAssetName)
            inset = 0
        case .photo:
            image = personalMark.image.map { Image(uiImage: $0) } ?? Image(initialOption.brandMarkAssetName)
            inset = size * photoFrame.insetFraction
        }
        return image.resizable().scaledToFit()
            .padding(inset)
            .frame(width: size, height: size)
            .background(Color(uiColor: PersonalBrandMarkStore.Frame.paper))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    private func testLaunchLink() {
        guard let url = LiveContainerLaunchLink.url(from: launchLink) else {
            launchMessage = "这不是 LiveContainer 的 App 启动链接。请从容器菜单重新复制，不要粘贴网页地址。"
            return
        }
        openURL(url) { accepted in
            Task { @MainActor in
                launchMessage = accepted ? "iOS 已交给 LiveContainer。请确认打开的是纸间。"
                    : "iOS 没找到该容器的打开方式。检查复制的是当前安装的容器链接。"
            }
        }
    }

    private func exportSelectedArtwork() {
        switch artwork {
        case .builtIn(let option):
            export(UIImage(named: option.brandMarkAssetName), identifier: option.rawValue)
        case .photo:
            let image = personalMark.image.map { PersonalBrandMarkStore.shortcutIcon(from: $0, frame: photoFrame) }
            export(image, identifier: "相册自定义")
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
