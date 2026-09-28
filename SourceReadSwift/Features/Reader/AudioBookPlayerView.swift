import SwiftUI

struct AudioBookPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator = AudioBookPlaybackCoordinator.shared
    @State private var isDraggingSlider = false
    @State private var dragSliderValue: Double = 0
    @State private var showChapterDrawer = false
    @State private var showSleepTimerDialog = false

    private let speedOptions: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            ZStack {
                // Background Ambient Glow
                ambientBackground

                VStack(spacing: 0) {
                    Spacer(minLength: 16)

                    // Cover Art
                    coverArtSection
                        .padding(.horizontal, 40)

                    Spacer(minLength: 24)

                    // Title & Metadata
                    titleMetadataSection
                        .padding(.horizontal, 28)

                    Spacer(minLength: 20)

                    // Progress Slider
                    progressSliderSection
                        .padding(.horizontal, 28)

                    Spacer(minLength: 20)

                    // Main Controls
                    mainPlaybackControls
                        .padding(.horizontal, 20)

                    Spacer(minLength: 24)

                    // Bottom Utility Toolbar
                    bottomUtilityBar
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(coordinator.currentBook?.name ?? "有声书")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let sourceName = coordinator.currentSource?.bookSourceName {
                            Text(sourceName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showChapterDrawer = true
                    } label: {
                        Image(systemName: "list.bullet.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showChapterDrawer) {
                audioChapterDrawer
            }
            .confirmationDialog("睡眠定时器", isPresented: $showSleepTimerDialog, titleVisibility: .visible) {
                Button("关闭定时器") {
                    coordinator.setSleepTimer(minutes: nil)
                }
                Button("15 分钟后") {
                    coordinator.setSleepTimer(minutes: 15)
                }
                Button("30 分钟后") {
                    coordinator.setSleepTimer(minutes: 30)
                }
                Button("45 分钟后") {
                    coordinator.setSleepTimer(minutes: 45)
                }
                Button("60 分钟后") {
                    coordinator.setSleepTimer(minutes: 60)
                }
                Button("播完本章后") {
                    coordinator.setSleepTimer(minutes: 0)
                }
                Button("取消", role: .cancel) {}
            } message: {
                if let remaining = coordinator.sleepTimerMinutesRemaining {
                    Text("当前剩余: \(remaining) 分钟")
                } else if coordinator.stopAtChapterEnd {
                    Text("当前设置: 播完本章后停止")
                } else {
                    Text("请选择定时暂停时间")
                }
            }
        }
    }

    // MARK: - View Components

    private var ambientBackground: some View {
        GeometryReader { proxy in
            if let coverUrl = coordinator.currentBook?.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .blur(radius: 60)
                            .opacity(0.25)
                    } else {
                        Color(.systemGroupedBackground)
                    }
                }
            } else {
                Color(.systemGroupedBackground)
            }
        }
        .ignoresSafeArea()
    }

    private var coverArtSection: some View {
        ZStack {
            if let coverUrl = coordinator.currentBook?.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure, .empty:
                        defaultCoverArt
                    @unknown default:
                        defaultCoverArt
                    }
                }
            } else {
                defaultCoverArt
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var defaultCoverArt: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "headphones")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var titleMetadataSection: some View {
        VStack(spacing: 8) {
            Text(coordinator.currentChapter?.title ?? "加载中...")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                if let author = coordinator.currentBook?.author, !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if coordinator.chapters.count > 0 {
                    Text("· 第 \(coordinator.currentChapterIndex + 1)/\(coordinator.chapters.count) 回")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = coordinator.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重试") {
                        coordinator.playChapter(at: coordinator.currentChapterIndex)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
                }
                .padding(.top, 4)
            }
        }
    }

    private var progressSliderSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isDraggingSlider ? dragSliderValue : coordinator.currentTime },
                    set: { dragSliderValue = $0 }
                ),
                in: 0...max(1, coordinator.duration),
                onEditingChanged: { editing in
                    isDraggingSlider = editing
                    if !editing {
                        coordinator.seek(to: dragSliderValue)
                    }
                }
            )
            .tint(Color.accentColor)

            HStack {
                let displayedCurrent = isDraggingSlider ? dragSliderValue : coordinator.currentTime
                Text(formatDuration(displayedCurrent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                if coordinator.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Spacer()

                let remaining = max(0, coordinator.duration - displayedCurrent)
                Text("-\(formatDuration(remaining))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mainPlaybackControls: some View {
        HStack(spacing: 28) {
            // Previous Chapter
            Button {
                coordinator.playPreviousChapter()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundStyle(coordinator.currentChapterIndex > 0 ? .primary : .tertiary)
            }
            .disabled(coordinator.currentChapterIndex <= 0)

            // Skip Backward 15s
            Button {
                coordinator.skip(seconds: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title)
                    .foregroundStyle(.primary)
            }

            // Play / Pause / Loading
            Button {
                coordinator.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 68, height: 68)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 10, x: 0, y: 4)

                    if coordinator.isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    } else {
                        Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .offset(x: coordinator.isPlaying ? 0 : 2)
                    }
                }
            }

            // Skip Forward 30s
            Button {
                coordinator.skip(seconds: 30)
            } label: {
                Image(systemName: "goforward.30")
                    .font(.title)
                    .foregroundStyle(.primary)
            }

            // Next Chapter
            Button {
                coordinator.playNextChapter()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundStyle(coordinator.currentChapterIndex + 1 < coordinator.chapters.count ? .primary : .tertiary)
            }
            .disabled(coordinator.currentChapterIndex + 1 >= coordinator.chapters.count)
        }
    }

    private var bottomUtilityBar: some View {
        HStack {
            // Speed Menu
            Menu {
                ForEach(speedOptions, id: \.self) { speed in
                    Button {
                        coordinator.setPlaybackRate(speed)
                    } label: {
                        HStack {
                            Text(String(format: "%.2fx", speed))
                            if coordinator.playbackRate == speed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                    Text(String(format: "%.2fx", coordinator.playbackRate))
                        .monospacedDigit()
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            // Sleep Timer
            Button {
                showSleepTimerDialog = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: coordinator.sleepTimerMinutesRemaining != nil || coordinator.stopAtChapterEnd ? "moon.fill" : "moon")
                    if let remaining = coordinator.sleepTimerMinutesRemaining {
                        Text("\(remaining)m")
                            .monospacedDigit()
                    } else if coordinator.stopAtChapterEnd {
                        Text("章末")
                    } else {
                        Text("定时")
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(coordinator.sleepTimerMinutesRemaining != nil || coordinator.stopAtChapterEnd ? Color.accentColor : .primary)
            }
        }
    }

    private var audioChapterDrawer: some View {
        NavigationStack {
            List {
                ForEach(coordinator.chapters.indices, id: \.self) { idx in
                    let chapter = coordinator.chapters[idx]
                    Button {
                        coordinator.playChapter(at: idx)
                        showChapterDrawer = false
                    } label: {
                        HStack {
                            Text("\(idx + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)

                            Text(chapter.title)
                                .font(.body)
                                .foregroundStyle(idx == coordinator.currentChapterIndex ? Color.accentColor : .primary)
                                .lineLimit(1)

                            Spacer()

                            if idx == coordinator.currentChapterIndex {
                                Image(systemName: coordinator.isPlaying ? "waveform" : "pause.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("有声节目单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showChapterDrawer = false
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
