import SwiftUI

struct ReaderNavigationStyleSettings: View {
    @AppStorage(ReaderNavigationStyle.defaultsKey) private var effectRaw = ReaderNavigationStyle.defaultStyle.rawValue
    private var selected: ReaderNavigationStyle { ReaderNavigationStyle.resolve(effectRaw) }

    var body: some View {
        List {
            Section("当前效果") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: selected.symbol)
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.title).font(.headline)
                        Text(selected.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(AppThemeRowSurface())

            Section {
                ForEach(ReaderNavigationStyle.allCases) { effect in
                    Button {
                        effectRaw = effect.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: effect.symbol).foregroundStyle(AppTheme.accent).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(effect.title).font(.body.weight(.medium))
                                Text(effect.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if effect == selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent) }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(AppPressStyle())
                    .accessibilityAddTraits(effect == selected ? .isSelected : [])
                    .accessibilityIdentifier("settings.readerTransition." + effect.rawValue)
                }
            } header: {
                Text("进入与返回阅读器")
            } footer: {
                Text("默认使用 iOS 原生 Zoom 缩放展开（主页常驻不重载），也可切换为 100% 系统原生推入与跟手边缘侧滑。")
            }
            .listRowBackground(AppThemeRowSurface())
        }
        .listStyle(.insetGrouped)
        .pageBackground()
        .navigationTitle("阅读页面转场")
        .navigationBarTitleDisplayMode(.inline)
    }
}
