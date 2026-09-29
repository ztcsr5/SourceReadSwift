import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var audioCoordinator = AudioBookPlaybackCoordinator.shared
    @State private var selectedTab = 0
    @State private var showFullAudioPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Only keep the active root alive.  The previous opacity-based
            // stack rendered three complete navigation trees every frame,
            // which was especially visible on long bookshelf lists.
            Group {
                switch selectedTab {
                case 0:
                    BookshelfView()
                        .transition(.opacity)
                case 1:
                    DiscoverView(viewModel: appState.discoverViewModel)
                        .transition(.opacity)
                default:
                    SettingsView()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Reserve space for the floating tab bar and mini player instead of letting the
            // last row disappear underneath it on every root scroll view.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !appState.isTabChromeHidden {
                    Color.clear.frame(height: audioCoordinator.currentBook != nil ? 144 : 86)
                }
            }

            if !appState.isTabChromeHidden {
                VStack(spacing: 8) {
                    if audioCoordinator.currentBook != nil {
                        miniAudioPlayerBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    customTabBar
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10)
            }
        }
        // Let SwiftUI lift the tab bar with the keyboard. The previous
        // keyboard-ignore modifier left the bar underneath the input accessory
        // and made the bottom controls feel blocked on small screens.
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: appState.isTabChromeHidden)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: audioCoordinator.currentBook != nil)
        .animation(.easeOut(duration: 0.16), value: selectedTab)
        .onChange(of: selectedTab) { _ in
            dismissKeyboard()
        }
        .sheet(isPresented: $showFullAudioPlayer) {
            AudioBookPlayerView()
        }
    }

    private var miniAudioPlayerBar: some View {
        Button {
            showFullAudioPlayer = true
        } label: {
            HStack(spacing: 12) {
                AsyncBookCover(urlString: audioCoordinator.currentBook?.coverUrl, width: 38, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(audioCoordinator.currentBook?.name ?? "有声书播放中")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(audioCoordinator.currentChapter?.title ?? "正在缓冲音频...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    audioCoordinator.togglePlayPause()
                } label: {
                    Image(systemName: audioCoordinator.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    audioCoordinator.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassPanel(cornerRadius: 18, material: .ultraThinMaterial, strokeOpacity: 0.10, shadowOpacity: 0.14)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private var customTabBar: some View {
        VStack(spacing: 0) {
            HStack {
                tabButton(index: 0, title: "主页", systemImage: "house")
                Spacer()
                tabButton(index: 1, title: "发现", systemImage: "square.grid.2x2")
                Spacer()
                tabButton(index: 2, title: "设置", systemImage: "gearshape")
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 9)
            .glassPanel(cornerRadius: 28, material: .ultraThinMaterial, strokeOpacity: 0.08, shadowOpacity: 0.16)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    private func tabButton(index: Int, title: String, systemImage: String) -> some View {
        Button {
            switchToTab(index)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == index ? "\(systemImage).fill" : systemImage)
                    .font(.system(size: 22, weight: selectedTab == index ? .bold : .medium))
                    .foregroundStyle(selectedTab == index ? AppTheme.accent : .secondary)
                    .frame(width: 46, height: 28)
                    .background {
                        if selectedTab == index {
                            Capsule()
                                .fill(AppTheme.accent.opacity(0.14))
                        }
                    }

                Text(title)
                    .font(.system(size: 11, weight: selectedTab == index ? .bold : .medium))
                    .foregroundStyle(selectedTab == index ? AppTheme.accent : .secondary)
            }
            .frame(width: 64, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(RootTabPressableButtonStyle())
    }

    private func switchToTab(_ index: Int) {
        guard selectedTab != index else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedTab = index
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct RootTabPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.105), value: configuration.isPressed)
    }
}
