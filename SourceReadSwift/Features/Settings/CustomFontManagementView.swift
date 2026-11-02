import SwiftUI
import UniformTypeIdentifiers

struct CustomFontManagementView: View {
    @StateObject private var fontManager = CustomFontManager.shared
    @AppStorage("reader.fontFamily") private var fontFamilyRawValue: String = ReaderFontFamily.system.rawValue
    @AppStorage("reader.customFontPostScriptName") private var customFontPostScriptName: String = ""
    @State private var isImportingFont = false
    @State private var importErrorMessage: String?
    @State private var showingErrorAlert = false
    @State private var isPreparingFont = false
    @State private var importedFontTitle: String?
    @State private var pendingFontURL: URL?

    private var currentFontFamily: ReaderFontFamily {
        ReaderFontFamily(rawValue: fontFamilyRawValue) ?? .system
    }

    private var allowedFontTypes: [UTType] {
        // Some cloud providers label TTF/TTC as generic items, making a font-only picker grey them out.
        // The import boundary validates extension, size and CoreText descriptors instead.
        [.item]
    }

    init() {}

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("字体预览", systemImage: "textformat")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(currentFontTitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                    Text("落霞与孤鹜齐飞，秋水共长天一色。天地玄黄，宇宙洪荒。")
                        .font(currentFontFamily.swiftUIFont(size: 18, customPostScriptName: customFontPostScriptName))
                        .padding(.vertical, 6)
                        .lineSpacing(4)
                }
                .padding(.vertical, 4)
            } header: {
                Text("当前排版字体")
            }
            .listRowBackground(AppThemeRowSurface())

            Section {
                ForEach([ReaderFontFamily.system, .light, .bold, .songti, .kaiti, .rounded, .maShanZheng, .zhiMangXing], id: \.self) { family in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(family.title)
                                .font(family.swiftUIFont(size: 16))
                            Text(systemFontDescription(for: family))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if currentFontFamily == family {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        fontFamilyRawValue = family.rawValue
                        HapticFeedback.light()
                    }
                }
            } header: {
                Text("内置字体")
            }
            .listRowBackground(AppThemeRowSurface())

            Section {
                if fontManager.installedFonts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("暂无导入的自定义字体")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("支持导入 TTF、OTF、TTC 格式字体，导入后可即时生效应用于阅读排版。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(fontManager.installedFonts) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayName)
                                    .font(ReaderFontFamily.custom.swiftUIFont(size: 16, customPostScriptName: item.postScriptName))
                                HStack(spacing: 8) {
                                    Text(item.fileName)
                                    Text("·")
                                    Text(item.formattedSize)
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            if currentFontFamily == .custom && customFontPostScriptName == item.postScriptName {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            customFontPostScriptName = item.postScriptName
                            fontFamilyRawValue = ReaderFontFamily.custom.rawValue
                            HapticFeedback.light()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                if currentFontFamily == .custom && customFontPostScriptName == item.postScriptName {
                                    fontFamilyRawValue = ReaderFontFamily.system.rawValue
                                    customFontPostScriptName = ""
                                }
                                fontManager.deleteFont(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    isImportingFont = true
                } label: {
                    Label(isPreparingFont ? "正在读取并启用字体…" : "从“文件”导入字体", systemImage: "plus.circle.fill")
                        .font(.body)
                }
                .disabled(isPreparingFont)
                if isPreparingFont {
                    HStack(spacing: 12) { ProgressView(); Text("正在复制文件和解析字体，请稍候") }
                        .font(.subheadline).accessibilityLabel("正在导入字体")
                } else if let importedFontTitle {
                    Label("已启用 · \(importedFontTitle)", systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if let importErrorMessage {
                    Label(importErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("自定义导入字体")
            } footer: {
                Text("支持 TTF、OTF、TTC、OTC。网盘文件请先下载；压缩包请先解压。文件列表允许选择普通文件，选中后会校验是否为有效字体。")
            }
            .listRowBackground(AppThemeRowSurface())
        }
        .pageBackground()
        .navigationTitle("字体管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isImportingFont, onDismiss: importPendingFont) {
            UniversalDocumentPicker(contentTypes: allowedFontTypes, opensAllFiles: false,
                onPick: { urls in
                    isImportingFont = false
                    guard let url = urls.first, !isPreparingFont else { return }
                    // The native delegate fires before dismissal; acknowledge the pick immediately.
                    isPreparingFont = true
                    importedFontTitle = nil
                    importErrorMessage = nil
                    pendingFontURL = url
                }, onCancel: { isImportingFont = false })
                .ignoresSafeArea()
        }
        .alert("字体导入提示", isPresented: $showingErrorAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "导入字体失败，请检查字体文件是否损坏。")
        }
    }

    private func importPendingFont() {
        guard let url = pendingFontURL else { return }
        pendingFontURL = nil
        Task { @MainActor in
            defer { isPreparingFont = false }
            do {
                let imported = try await fontManager.importPickedFont(from: url)
                customFontPostScriptName = imported.postScriptName
                fontFamilyRawValue = ReaderFontFamily.custom.rawValue
                importedFontTitle = imported.displayName
                HapticFeedback.success()
            } catch {
                importErrorMessage = "导入字体失败：\(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }

    private var currentFontTitle: String {
        if currentFontFamily == .custom {
            if let matched = fontManager.installedFonts.first(where: { $0.postScriptName == customFontPostScriptName }) {
                return matched.displayName
            }
            return "自定义字体"
        }
        return currentFontFamily.title
    }

    private func systemFontDescription(for family: ReaderFontFamily) -> String {
        switch family {
        case .system: return "iOS 苹方标准系统字体，清晰易读"
        case .light: return "苹方细体，轻盈优雅"
        case .bold: return "苹方粗体，端庄有力"
        case .songti: return "传统宋体衬线字，具有典雅纸质韵味"
        case .kaiti: return "经典楷体笔触，笔意连贯自然"
        case .rounded: return "圆润温和，视觉柔和不刺眼"
        case .maShanZheng: return "内置开源楷书，笔画有力度，适合古风阅读"
        case .zhiMangXing: return "内置开源行书，轻快手写感；长篇可优先使用常规或楷体"
        case .custom: return "用户自定义导入"
        }
    }
}
