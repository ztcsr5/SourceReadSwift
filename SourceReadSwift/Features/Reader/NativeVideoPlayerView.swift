import AVKit
import SwiftUI

/// Presents AVKit's video controls with a separate source-backed episode directory.
struct VideoPlayerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nativeReaderSession) private var nativeSession
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = VideoPlaybackSession()
    let bookID: String?
    let bookTitle: String
    let source: BookSource
    let initialChapterIndex: Int
    let initialPositionSeconds: Double?
    let chapters: [BookChapter]
    let engine: SourceEngine
    let onRequestExit: (() -> Void)?
    @State private var showsEpisodes = false
    @State private var episodeSearch = ""
    @State private var reversesEpisodes = false
    @State private var isLocked = false
    @State private var fillsScreen = false
    @AppStorage("video_dimming_level") private var dimming = 0.0

    init(bookID: String? = nil, bookTitle: String, source: BookSource, initialChapterIndex: Int,
         initialPositionSeconds: Double? = nil, chapters: [BookChapter], engine: SourceEngine,
         onRequestExit: (() -> Void)? = nil, playbackSession: VideoPlaybackSession? = nil) {
        _playback = StateObject(wrappedValue: playbackSession ?? VideoPlaybackSession())
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.source = source
        self.initialChapterIndex = initialChapterIndex
        self.initialPositionSeconds = initialPositionSeconds
        self.chapters = chapters
        self.engine = engine
        self.onRequestExit = onRequestExit
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            NativeVideoSurface(playback: playback, fillsScreen: fillsScreen, isLocked: isLocked)
                .accessibilityIdentifier("video.nativePlayer")
            Color.black.opacity(min(max(dimming, 0), 0.8)).allowsHitTesting(false)
            if isLocked { Color.clear.contentShape(Rectangle()) }
            if playback.isLoading {
                ProgressView("正在加载视频…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)
            }
            if let failure = playback.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "play.slash").font(.largeTitle)
                    Text(failure).multilineTextAlignment(.center)
                    Button("重试") { playback.playEpisode(at: playback.episodeOffset) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("video.retry")
                }
                .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(24)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .hideRootTabBar()
        .readerOpeningContentReady()
        .task {
            playback.start(.init(bookID: bookID, title: bookTitle, source: source, chapters: chapters,
                initialChapterIndex: initialChapterIndex, initialPositionSeconds: initialPositionSeconds,
                engine: engine, bookshelf: appState.bookshelfStore))
        }
        .onChange(of: scenePhase) { phase in if phase != .active { playback.persistProgress() } }
        .onDisappear {
            if !showsEpisodes, !playback.isPresentingFullScreen, !playback.isPictureInPictureActive { playback.stop() }
        }
        .background(ReaderNativeLifecycleBridge(session: nativeSession, allowsReturn: !showsEpisodes && !isLocked,
            onExit: playback.stop, onSelectChapter: { index in
                if let offset = chapters.firstIndex(where: { $0.index == index }) { playback.playEpisode(at: offset) }
            }))
        .sheet(isPresented: $showsEpisodes) { episodeDirectory }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if isLocked {
                Button { isLocked = false } label: { Label("解锁", systemImage: "lock.open") }.frame(minHeight: 44)
            } else {
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("关闭视频").accessibilityIdentifier("video.close")
                VStack(alignment: .leading, spacing: 4) {
                    Text(bookTitle).font(.headline).lineLimit(1)
                    Text(playback.currentEpisode?.title ?? "视频").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("video.episodeTitle")
                }
                Spacer(minLength: 0)
                Button { showsEpisodes = true } label: { Image(systemName: "list.bullet").frame(width: 44, height: 44) }
                    .accessibilityLabel("剧集目录").accessibilityIdentifier("video.episodes")
                Menu {
                    Button { playback.playEpisode(at: playback.episodeOffset - 1) } label: { Label("上一集", systemImage: "backward.end") }
                        .disabled(playback.episodeOffset <= 0)
                    Button { playback.playEpisode(at: playback.episodeOffset + 1) } label: { Label("下一集", systemImage: "forward.end") }
                        .disabled(playback.episodeOffset + 1 >= chapters.count)
                    Toggle("自动连播", isOn: $playback.playsNextEpisode)
                    Toggle("填满画面", isOn: $fillsScreen)
                    Button { isLocked = true } label: { Label("锁定触控", systemImage: "lock") }
                    Menu("画面亮度") {
                        Button("正常") { dimming = 0 }
                        Button("柔暗") { dimming = 0.25 }
                        Button("夜间") { dimming = 0.5 }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("视频设置")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4).background(.regularMaterial)
        .buttonStyle(.plain)
    }

    private var episodeOffsets: [Int] {
        let query = episodeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let offsets = chapters.indices.filter { query.isEmpty || chapters[$0].title.localizedCaseInsensitiveContains(query) || "\($0 + 1)".contains(query) }
        return reversesEpisodes ? Array(offsets.reversed()) : offsets
    }

    private var episodeDirectory: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(episodeOffsets, id: \.self) { offset in
                    Button {
                        playback.playEpisode(at: offset)
                        showsEpisodes = false
                    } label: {
                        HStack {
                            Text(chapters[offset].title).foregroundStyle(.primary)
                            Spacer()
                            if offset == playback.episodeOffset { Image(systemName: "play.fill") }
                        }.contentShape(Rectangle())
                    }
                    .id(offset).accessibilityIdentifier("video.episode.\(offset)")
                }
                .onAppear { proxy.scrollTo(playback.episodeOffset, anchor: .center) }
            }
            .searchable(text: $episodeSearch, prompt: "搜索剧集")
            .navigationTitle("剧集目录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { reversesEpisodes.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }
                        .accessibilityLabel("正序倒序切换")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showsEpisodes = false }.accessibilityIdentifier("video.episodes.done")
                }
            }
        }
    }

    private func close() {
        playback.stop()
        if let onRequestExit { onRequestExit() } else { dismiss() }
    }
}

private struct NativeVideoSurface: UIViewControllerRepresentable {
    let playback: VideoPlaybackSession
    let fillsScreen: Bool
    let isLocked: Bool

    func makeCoordinator() -> Coordinator { Coordinator(playback: playback) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = playback.player
        controller.delegate = context.coordinator
        controller.updatesNowPlayingInfoCenter = false
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.videoGravity = fillsScreen ? .resizeAspectFill : .resizeAspect
        controller.showsPlaybackControls = !isLocked
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let playback: VideoPlaybackSession
        init(playback: VideoPlaybackSession) { self.playback = playback }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            playback.isPresentingFullScreen = true
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { context in
                if !context.isCancelled { self.playback.isPresentingFullScreen = false }
            }
        }

        func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            playback.isPictureInPictureActive = true
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            playback.isPictureInPictureActive = false
        }
    }
}
