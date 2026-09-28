import SwiftUI
import AVKit
import MediaPlayer

struct VideoPlayerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var bookID: String? = nil
    let bookTitle: String
    let source: BookSource
    let initialChapterIndex: Int
    let chapters: [BookChapter]
    let engine: SourceEngine

    @State private var currentChapterIndex: Int
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var showControls = true
    @State private var isDraggingSlider = false
    @State private var dragSliderValue: Double = 0
    @State private var showEpisodeDrawer = false
    @State private var controlsTimer: Timer?
    @State private var timeObserverToken: Any?

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    init(
        bookID: String? = nil,
        bookTitle: String,
        source: BookSource,
        initialChapterIndex: Int,
        chapters: [BookChapter],
        engine: SourceEngine
    ) {
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.source = source
        self.initialChapterIndex = initialChapterIndex
        self.chapters = chapters
        self.engine = engine
        self._currentChapterIndex = State(initialValue: initialChapterIndex)
    }

    var currentChapter: BookChapter? {
        guard chapters.indices.contains(currentChapterIndex) else { return nil }
        return chapters[currentChapterIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                            if showControls {
                                scheduleHideControls()
                            }
                        }
                    }
            }

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                    Text("正在解析视频流...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Button("重试") {
                        loadVideo(at: currentChapterIndex)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }

            if showControls {
                controlsOverlay
            }
        }
        .task {
            loadVideo(at: currentChapterIndex)
        }
        .sheet(isPresented: $showEpisodeDrawer) {
            episodeDrawerSheet
        }
        .onDisappear {
            cleanupPlayer()
        }
        .statusBarHidden(!showControls)
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            // Top Bar
            HStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let chapter = currentChapter {
                        Text(chapter.title)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Episode List
                Button {
                    showEpisodeDrawer = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.number")
                        Text("剧集")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // Center Play / Pause
            Button {
                togglePlayPause()
                scheduleHideControls()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 64, height: 64)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .offset(x: isPlaying ? 0 : 2)
                }
            }

            Spacer()

            // Bottom Bar
            VStack(spacing: 8) {
                // Slider
                Slider(
                    value: Binding(
                        get: { isDraggingSlider ? dragSliderValue : currentTime },
                        set: { dragSliderValue = $0 }
                    ),
                    in: 0...max(1, duration),
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if !editing {
                            seek(to: dragSliderValue)
                            scheduleHideControls()
                        }
                    }
                )
                .tint(AppTheme.accent)

                HStack {
                    let displayed = isDraggingSlider ? dragSliderValue : currentTime
                    Text(formatDuration(displayed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    // Previous / Next Episode buttons
                    HStack(spacing: 18) {
                        Button {
                            if currentChapterIndex > 0 {
                                loadVideo(at: currentChapterIndex - 1)
                            }
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.body)
                                .foregroundStyle(currentChapterIndex > 0 ? .white : .white.opacity(0.3))
                        }
                        .disabled(currentChapterIndex <= 0)

                        Button {
                            if currentChapterIndex + 1 < chapters.count {
                                loadVideo(at: currentChapterIndex + 1)
                            }
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.body)
                                .foregroundStyle(currentChapterIndex + 1 < chapters.count ? .white : .white.opacity(0.3))
                        }
                        .disabled(currentChapterIndex + 1 >= chapters.count)
                    }

                    Spacer()

                    // Speed Menu
                    Menu {
                        ForEach(speedOptions, id: \.self) { speed in
                            Button("\(String(format: "%.2fx", speed))") {
                                playbackRate = speed
                                player?.rate = speed
                            }
                        }
                    } label: {
                        Text(String(format: "%.2fx", playbackRate))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Text(formatDuration(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .transition(.opacity)
    }

    private var episodeDrawerSheet: some View {
        NavigationStack {
            List {
                ForEach(chapters.indices, id: \.self) { idx in
                    let chapter = chapters[idx]
                    Button {
                        loadVideo(at: idx)
                        showEpisodeDrawer = false
                    } label: {
                        HStack {
                            Text("\(idx + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            Text(chapter.title)
                                .font(.body)
                                .foregroundStyle(idx == currentChapterIndex ? Color.accentColor : .primary)
                                .lineLimit(1)
                            Spacer()
                            if idx == currentChapterIndex {
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("剧集列表 (\(chapters.count)集)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showEpisodeDrawer = false
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func loadVideo(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentChapterIndex = index
        let chapter = chapters[index]
        isLoading = true
        errorMessage = nil
        cleanupPlayer()

        if let bookID, !bookID.isEmpty {
            appState.bookshelfStore.updateReadingProgress(
                bookID: bookID,
                chapterIndex: index,
                chapterTitle: chapter.title,
                totalChapters: chapters.count
            )
        }

        Task {
            let result = await engine.getContent(source: source, chapter: chapter)
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success(let content):
                    if let videoUrlString = VideoContentParser.parseVideoURL(from: content, chapterURL: chapter.url),
                       let url = URL(string: videoUrlString) {
                        self.setupPlayer(with: url)
                    } else {
                        self.errorMessage = "未在当前剧集解析到有效视频流地址"
                    }
                case .failure(let error):
                    self.errorMessage = error.displayMessage
                }
            }
        }
    }

    private func setupPlayer(with url: URL) {
        cleanupPlayer()

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            if currentChapterIndex + 1 < chapters.count {
                loadVideo(at: currentChapterIndex + 1)
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = time.seconds
            if let currentItem = self.player?.currentItem, currentItem.duration.isNumeric {
                self.duration = currentItem.duration.seconds
            }
        }

        newPlayer.play()
        newPlayer.rate = playbackRate
        isPlaying = true
        scheduleHideControls()
    }

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func scheduleHideControls() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                if isPlaying {
                    showControls = false
                }
            }
        }
    }

    private func cleanupPlayer() {
        controlsTimer?.invalidate()
        controlsTimer = nil
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
        currentTime = 0
        duration = 0
        isPlaying = false
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
