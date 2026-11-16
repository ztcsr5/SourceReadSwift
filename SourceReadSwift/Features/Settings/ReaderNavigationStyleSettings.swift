import SwiftUI

struct ReaderNavigationStyleSettings: View {
    @AppStorage(ReaderNavigationStyle.defaultsKey) private var effectRaw = ReaderNavigationStyle.system.rawValue
    @AppMotion private var motion
    @State private var previewOpen = true
    private var selected: ReaderNavigationStyle { ReaderNavigationStyle.resolve(effectRaw) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    preview
                    Button(previewOpen ? "预览返回" : "预览进入") {
                        withAnimation(motion.animation(.navigation)) { previewOpen.toggle() }
                    }
                    .buttonStyle(AppPressStyle())
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("settings.readerTransition.preview")
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(AppThemeRowSurface())

            Section {
                ForEach(ReaderNavigationStyle.allCases) { effect in
                    Button {
                        effectRaw = effect.rawValue
                        previewOpen = true
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
                Text("书封开合与跟手收书会保留背后的页面，从原封面位置展开；收书时仅移动画面副本。开启减少动态效果后改为淡出。")
            }
            .listRowBackground(AppThemeRowSurface())
        }
        .listStyle(.insetGrouped)
        .pageBackground()
        .navigationTitle("阅读页面转场")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preview: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12).fill(AppTheme.accent.opacity(0.13))
            Image(systemName: "book.closed").font(.title2).foregroundStyle(AppTheme.accent).padding(.leading, 18)
            if previewOpen {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.card)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("第十二章").font(.headline)
                            ForEach(0..<2) { _ in
                                Capsule().fill(.primary.opacity(0.14)).frame(width: 96, height: 4)
                            }
                        }
                        .padding(.leading, 20)
                    }
                    .transition(previewTransition)
            }
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private var previewTransition: AnyTransition {
        if motion.reducesMotion { return .identity }
        switch selected {
        case .system: return .move(edge: .trailing)
        case .parallax: return .move(edge: .trailing).combined(with: .opacity)
        case .fade: return .opacity
        case .coverFlight, .coverInteractive: return .scale(scale: 0.18, anchor: .leading).combined(with: .opacity)
        }
    }
}
