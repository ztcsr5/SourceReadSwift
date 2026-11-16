import AVFoundation
import MediaPlayer

/// Owns a video's requests, native player, resume point and progress for one reader route.
@MainActor
final class VideoPlaybackSession: ObservableObject {
    struct Configuration {
        let bookID: String?
        let title: String
        let source: BookSource
        let chapters: [BookChapter]
        let initialChapterIndex: Int
        let initialPositionSeconds: Double?
        let engine: SourceEngine
        let bookshelf: BookshelfStore?
    }

    let player = AVPlayer()
    @Published private(set) var episodeOffset = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var playsNextEpisode = true
    var isPresentingFullScreen = false
    var isPictureInPictureActive = false
    private(set) var configuration: Configuration?
    private let playbackOwner = UUID()
    private var loadID = UUID()
    private var loadTask: Task<Void, Never>?
    private var itemObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var pendingResumeSeconds: Double?
    private var isSeeking = false
    private var seekID = UUID()
    private var lastSavedSecond = 0
    private let makePlayerItem: (MediaStreamRequest) -> AVPlayerItem

    init(makePlayerItem: @escaping (MediaStreamRequest) -> AVPlayerItem = { $0.makePlayerItem() }) {
        self.makePlayerItem = makePlayerItem
    }

    deinit {
        loadTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        for (command, target) in remoteTargets { command.removeTarget(target) }
        player.pause()
    }

    var currentEpisode: BookChapter? {
        guard let chapters = configuration?.chapters, chapters.indices.contains(episodeOffset) else { return nil }
        return chapters[episodeOffset]
    }

    func start(_ configuration: Configuration) {
        guard self.configuration == nil else { return }
        self.configuration = configuration
        episodeOffset = MediaPlaybackPolicy.episodeOffset(for: configuration.initialChapterIndex, in: configuration.chapters)
        guard !configuration.chapters.isEmpty else { errorMessage = "此书暂无可播放剧集"; return }
        playEpisode(at: episodeOffset, resumeSeconds: configuration.initialPositionSeconds)
    }

    func playEpisode(at offset: Int, resumeSeconds: Double? = nil) {
        guard let configuration, configuration.chapters.indices.contains(offset) else { return }
        persistProgress()
        releaseItem()
        MediaPlaybackOwnership.shared.claim(playbackOwner) { [weak self] in
            self?.stop()
            self?.errorMessage = "已切换至其他音频，可点按重试继续播放视频"
        }
        installRemoteCommands()
        episodeOffset = offset
        pendingResumeSeconds = resumeSeconds
        currentTime = 0
        duration = 0
        lastSavedSecond = 0
        isLoading = true
        errorMessage = nil
        let episode = configuration.chapters[offset]
        let generation = loadID
        loadTask = Task { [weak self] in
            defer { if self?.loadID == generation { self?.loadTask = nil } }
            if let stream = VideoContentParser.directPlaybackURL(episode.url, base: episode.bookUrl) {
                await self?.openStream(stream, episode: episode, generation: generation)
                return
            }
            let result = await configuration.engine.getContent(source: configuration.source, chapter: episode)
            guard let self, !Task.isCancelled, self.loadID == generation else { return }
            switch result {
            case .success(let content):
                guard let stream = VideoContentParser.parseVideoURL(from: content, chapterURL: episode.url) else {
                    self.fail("当前剧集未返回可播放的视频地址，请重试或更换书源")
                    return
                }
                await self.openStream(stream, episode: episode, generation: generation)
            case .failure(let error): self.fail(error.displayMessage)
            }
        }
    }

    func play() {
        guard player.currentItem != nil, player.currentItem?.status != .failed else { return }
        if duration > 0, currentTime >= duration { seek(to: 0) }
        player.play()
    }

    func pause() {
        player.pause()
        persistProgress()
        updateNowPlaying()
    }

    func seek(to second: Double) {
        guard second.isFinite, duration.isFinite, duration > 0 else { return }
        let target = min(max(second, 0), duration)
        let generation = loadID
        seekID = UUID()
        let request = seekID
        isSeeking = true
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.loadID == generation, self.seekID == request else { return }
                self.isSeeking = false
                guard finished else { return }
                self.currentTime = target
                self.persistProgress()
                self.updateNowPlaying()
            }
        }
    }

    func stop() {
        persistProgress()
        releaseItem()
        isLoading = false
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets.removeAll()
        if MediaPlaybackOwnership.shared.release(playbackOwner) { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }

    /// Flushes a settled position on backgrounding or route exit; never saves the pre-resume zero.
    func persistProgress() {
        guard player.currentItem?.status == .readyToPlay, pendingResumeSeconds == nil, !isSeeking,
              let configuration, let bookID = configuration.bookID, let episode = currentEpisode,
              let second = MediaPlaybackPolicy.recordedSecond(currentTime) else { return }
        lastSavedSecond = second
        configuration.bookshelf?.updateReadingProgress(bookID: bookID, chapterIndex: episode.index,
            chapterTitle: episode.title, totalChapters: max(configuration.chapters.count, (configuration.chapters.last?.index ?? 0) + 1),
            paragraphIndex: second)
    }

    private func openStream(_ reference: String, episode: BookChapter, generation: UUID) async {
        guard !Task.isCancelled, loadID == generation, let configuration else { return }
        let resolved = await MediaStreamRequest.resolve(reference, source: configuration.source,
            episode: episode, engine: configuration.engine)
        guard !Task.isCancelled, loadID == generation else { return }
        let request: MediaStreamRequest
        switch resolved {
        case .success(let prepared): request = prepared
        case .failure(let error): fail(error.displayMessage); return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            fail("无法启用视频声音，请结束其他音频会话后重试")
            return
        }
        installItem(makePlayerItem(request))
    }

    private func installItem(_ item: AVPlayerItem) {
        let generation = loadID
        player.replaceCurrentItem(with: item)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.loadID == generation, self.player.currentItem === item else { return }
                if item.status == .failed { self.fail("视频无法播放，可能是格式不支持或地址已过期，请重试") }
                if item.status == .readyToPlay { self.updateDuration(item); self.updateNowPlaying() }
            }
        }
        durationObservation = item.observe(\.duration, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.loadID == generation, self.player.currentItem === item else { return }
                self.updateDuration(item)
            }
        }
        playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.loadID == generation else { return }
                self.isLoading = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.updateNowPlaying()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.loadID == generation, self.player.currentItem === item else { return }
                self.persistProgress()
                if self.playsNextEpisode, let count = self.configuration?.chapters.count, self.episodeOffset + 1 < count {
                    self.playEpisode(at: self.episodeOffset + 1)
                } else { self.pause() }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.loadID == generation, self.player.currentItem === item, !self.isSeeking else { return }
                // A queued observation may predate a completed seek. Read the player's
                // current clock on this actor turn instead of restoring that stale timestamp.
                let second = self.player.currentTime().seconds
                guard second.isFinite else { return }
                self.currentTime = max(0, second)
                self.updateDuration(item)
                if let second = MediaPlaybackPolicy.recordedSecond(self.currentTime), abs(second - self.lastSavedSecond) >= 3 { self.persistProgress() }
                self.updateNowPlaying()
            }
        }
        player.play()
    }

    private func updateDuration(_ item: AVPlayerItem) {
        guard item.duration.seconds.isFinite, item.duration.seconds > 0 else { return }
        duration = item.duration.seconds
        switch MediaPlaybackPolicy.resume(at: pendingResumeSeconds, duration: duration) {
        case .seek(let second): pendingResumeSeconds = nil; seek(to: second)
        case .fromStart: pendingResumeSeconds = nil
        case .waitForDuration: break
        }
    }

    private func releaseItem() {
        loadID = UUID()
        loadTask?.cancel()
        loadTask = nil
        seekID = UUID()
        isSeeking = false
        itemObservation?.invalidate()
        durationObservation?.invalidate()
        playbackObservation?.invalidate()
        itemObservation = nil
        durationObservation = nil
        playbackObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func fail(_ message: String) {
        player.pause()
        isLoading = false
        errorMessage = message
    }

    private func installRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.play() }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.player.timeControlStatus == .paused ? $0.play() : $0.pause() }
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.preferredIntervals = [10]
        register(center.skipBackwardCommand) { $0.seek(to: $0.currentTime - 10) }
        register(center.skipForwardCommand) { $0.seek(to: $0.currentTime + 10) }
        register(center.nextTrackCommand) { $0.playEpisode(at: $0.episodeOffset + 1) }
        register(center.previousTrackCommand) { $0.playEpisode(at: $0.episodeOffset - 1) }
        center.changePlaybackPositionCommand.isEnabled = true
        let positionTarget = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                guard let self, MediaPlaybackOwnership.shared.owns(self.playbackOwner) else { return }
                self.seek(to: position.positionTime)
            }
            return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, positionTarget))
    }

    private func register(_ command: MPRemoteCommand, action: @escaping (VideoPlaybackSession) -> Void) {
        command.isEnabled = true
        let target = command.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, MediaPlaybackOwnership.shared.owns(self.playbackOwner) else { return }
                action(self)
            }
            return .success
        }
        remoteTargets.append((command, target))
    }

    private func updateNowPlaying() {
        guard MediaPlaybackOwnership.shared.owns(playbackOwner), let episode = currentEpisode else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyAlbumTitle: configuration?.title ?? "视频", MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyPlaybackRate: player.rate]
    }
}
