import PhotosUI
import SwiftUI

struct PersonalBrandMarkSettings: View {
    @AppStorage(PersonalBrandMarkStore.enabledKey) private var usesPhoto = false
    @AppStorage(PersonalBrandMarkStore.frameKey) private var frameRaw = PersonalBrandMarkStore.Frame.full.rawValue
    @ObservedObject private var personalMark = PersonalBrandMarkStore.shared
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isWorking = false
    @State private var confirmsRemoval = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    PaperBetweenMark(size: 68)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设置与关于页预览").font(.headline)
                        Text(usesPhoto && personalMark.image != nil ? "使用相册徽标" : "跟随桌面图标")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(AppThemeRowSurface())

            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(personalMark.image == nil ? "从相册选择图片" : "更换图片", systemImage: "photo")
                }
                .disabled(isWorking)
                if isWorking { ProgressView("正在处理图片") }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if personalMark.image != nil {
                    Toggle("使用相册徽标", isOn: $usesPhoto)
                    Picker("装裱", selection: $frameRaw) {
                        ForEach(PersonalBrandMarkStore.Frame.allCases) { frame in
                            Text(frame.title).tag(frame.rawValue)
                        }
                    }
                    .disabled(!usesPhoto)
                    NavigationLink {
                        HomeScreenIconExportView(initialOption: AppIconOption.current(), prefersPersonalMark: true)
                    } label: {
                        Label("导出同款主屏幕图标", systemImage: "square.and.arrow.up")
                    }
                    Button("移除相册徽标", role: .destructive) { confirmsRemoval = true }
                        .disabled(isWorking)
                }
            } footer: {
                Text("照片只保存在本机。把相同的裁切和纸边导出后，可在快捷指令中手动做成主屏幕图标。")
            }
            .listRowBackground(AppThemeRowSurface())
        }
        .pageBackground()
        .navigationTitle("相册自定义徽标")
        .navigationBarTitleDisplayMode(.inline)
        .task { await personalMark.loadIfNeeded() }
        .onChange(of: selectedPhoto) { photo in
            guard let photo else { return }
            Task { await importPhoto(photo) }
        }
        .confirmationDialog("移除 App 内保存的相册徽标？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("移除相册徽标", role: .destructive) { Task { await removePhoto() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移除后徽标跟随桌面图标。原照片不会删除。")
        }
    }

    private func importPhoto(_ photo: PhotosPickerItem) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false; selectedPhoto = nil }
        do {
            guard let bytes = try await photo.loadTransferable(type: Data.self) else {
                throw PersonalBrandMarkStore.Failure.invalidPhoto
            }
            try await personalMark.savePhoto(bytes)
            usesPhoto = true
        } catch {
            errorMessage = "未能保存相册徽标：\(error.localizedDescription)"
        }
    }

    private func removePhoto() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await personalMark.removePhoto()
            usesPhoto = false
        } catch {
            errorMessage = "未能移除相册徽标：\(error.localizedDescription)"
        }
    }
}
