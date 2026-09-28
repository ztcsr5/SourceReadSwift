import SwiftUI
import UniformTypeIdentifiers

struct CustomFontManagementView: View {
    @StateObject private var fontManager = CustomFontManager.shared
    @AppStorage("reader.fontFamily") private var fontFamilyRawValue: String = ReaderFontFamily.system.rawValue
    @AppStorage("reader.customFontPostScriptName") private var customFontPostScriptName: String = ""
    @State private var isImportingFont = false
    @State private var importErrorMessage: String?
    @State private var showingErrorAlert = false

    private var currentFontFamily: ReaderFontFamily {
        ReaderFontFamily(rawValue: fontFamilyRawValue) ?? .system
    }

    private var allowedFontTypes: [UTType] {
        var types: [UTType] = [.font]
        if let ttf = UTType(filenameExtension: "ttf") { types.append(ttf) }
        if let otf = UTType(filenameExtension: "otf") { types.append(otf) }
        if let ttc = UTType(filenameExtension: "ttc") { types.append(ttc) }
        return types
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

            Section {
                ForEach([ReaderFontFamily.system, .light, .bold, .songti, .kaiti, .rounded], id: \.self) { family in
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
                    Label("从“文件”导入字体 (.ttf / .otf)", systemImage: "plus.circle.fill")
                        .font(.body)
                }
            } header: {
                Text("自定义导入字体")
            } footer: {
                Text("从微信、百度网盘或 iCloud Drive 下载的字体文件均可通过系统“文件”导入。")
            }
        }
        .navigationTitle("字体管理")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImportingFont,
            allowedContentTypes: allowedFontTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let imported = try fontManager.importFont(from: url)
                    customFontPostScriptName = imported.postScriptName
                    fontFamilyRawValue = ReaderFontFamily.custom.rawValue
                    HapticFeedback.success()
                } catch {
                    importErrorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
        .alert("字体导入提示", isPresented: $showingErrorAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "导入字体失败，请检查字体文件是否损坏。")
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
        case .custom: return "用户自定义导入"
        }
    }
}
