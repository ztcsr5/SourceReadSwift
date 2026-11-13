import Foundation
import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class AudioBookPlaybackCoordinator: ObservableObject {
    static let shared = AudioBookPlaybackCoordinator()

    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var currentChapterIndex: Int = 0
    @Published var chapters: [BookChapter] = []
    @Published var currentBook: SearchBook?
    @Published var currentSource: BookSource?
    @Published var currentAudioURL: String?
    @Published var errorMessage: String?
    @Published var sleepTimerMinutesRemaining: Int?
    @Published var stopAtChapterEnd: Bool = false
    @Published var currentBookID: String?
    @Published var isFadeOutEnabled: Bool = true

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var chapterEndObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var artworkTask: Task<Void, Never>?
    private var artworkLoadID = UUID()
    private var shouldPlayWhenReady = false
    private var shouldResumeAfterInterruption = false
    private var seekID = UUID()
    private var isSeeking = false
    private var sleepTimer: Timer?
    private var fadeTimer: Timer?
    private var currentArtwork: MPMediaItemArtwork?
    private var currentEngine: SourceEngine?
    private var pendingResumeSeconds: Double?
    private var bookshelfStore: BookshelfStore?
    private var lastPersistedSecond: Int = 0

    var currentChapter: BookChapter? {
        guard chapters.indices.contains(currentChapterIndex) else { return nil }
        return chapters[currentChapterIndex]
    }

    var progress: Double {
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return 0 }
        return max(0, min(currentTime / duration, 1.0))
    }

    private init() {
        setupAudioSession()
        setupRemoteCommandCenter()
        setupNotificationObservers()
    }

    deinit {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        sleepTimer?.invalidate()
        fadeTimer?.invalidate()
        artworkTask?.cancel()
        chapterLoadTask?.cancel()
        if let chapterEndObserver { NotificationCenter.default.removeObserver(chapterEndObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    // MARK: - Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .allowBluetoothA2DP, .duckOthers])
            try session.setActive(true, options: [])
        } catch {
            print("[AudioBookPlaybackCoordinator] Failed to configure audio session: \(error)")
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.play()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else {
                Task { @MainActor [weak self] in self?.skip(seconds: 15) }
                return .success
            }
            Task { @MainActor [weak self] in
                self?.skip(seconds: skipEvent.interval)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent else {
                Task { @MainActor [weak self] in self?.skip(seconds: -15) }
                return .success
            }
            Task { @MainActor [weak self] in
                self?.skip(seconds: -skipEvent.interval)
            }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playNextChapter()
            }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playPreviousChapter()
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }

    private func setupNotificationObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            if type == .began {
                self.shouldResumeAfterInterruption = self.isPlaying
                self.pause()
            } else if type == .ended {
                defer { self.shouldResumeAfterInterruption = false }
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume), self.shouldResumeAfterInterruption {
                        self.play()
                    }
                }
            }
        }
    }

    // MARK: - Playback Control

    func startBook(
        bookID: String? = nil,
        book: SearchBook,
        source: BookSource,
        chapters: [BookChapter],
        initialChapterIndex: Int = 0,
        initialPositionSeconds: Double? = nil,
        engine: SourceEngine,
        bookshelfStore: BookshelfStore? = nil
    ) {
        stop()
        self.currentBookID = bookID
        self.currentBook = book
        self.currentSource = source
        self.chapters = chapters
        self.currentEngine = engine
        self.bookshelfStore = bookshelfStore
        self.currentChapterIndex = max(0, min(initialChapterIndex, chapters.count - 1))
        loadCoverArtwork(url: book.coverUrl)
        guard !chapters.isEmpty else {
            errorMessage = "此书暂无可播放章节"
            return
        }
        playChapter(at: self.currentChapterIndex, resumeSeconds: initialPositionSeconds)
    }

    private var chapterLoadTask: Task<Void, Never>?
    private var chapterLoadID = UUID()

    func playChapter(at index: Int, resumeSeconds: Double? = nil) {
        guard chapters.indices.contains(index) else { return }
        persistProgressIfNeeded(force: true)
        chapterLoadTask?.cancel()
        chapterLoadTask = nil
        chapterLoadID = UUID()
        let loadID = chapterLoadID
        releasePlayer()
        currentChapterIndex = index
        pendingResumeSeconds = resumeSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        lastPersistedSecond = 0
        shouldPlayWhenReady = true
        let chapter = chapters[index]
        isLoading = true
        errorMessage = nil
        updateNowPlayingInfo()

        // If audio url is already known in chapter url or content
        if let directURL = AudioContentParser.parseURL(chapter.url, base: chapter.url), AudioContentParser.isMediaURL(directURL) {
            setupPlayer(with: directURL)
            return
        }

        // Fetch chapter content from engine to obtain streaming audio link
        guard let source = currentSource, let engine = currentEngine else {
            isLoading = false
            errorMessage = "缺少书源引擎"
            return
        }

        chapterLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let contentResult = await engine.getContent(source: source, chapter: chapter)
            guard !Task.isCancelled, self.chapterLoadID == loadID else { return }
            self.chapterLoadTask = nil
            switch contentResult {
            case .success(let content):
                if let audioURL = AudioContentParser.parseURL(content.text, base: chapter.url) {
                    self.setupPlayer(with: audioURL)
                } else {
                    self.isLoading = false
                    self.errorMessage = "未找到音频播放流地址"
                }
            case .failure(let error):
                self.isLoading = false
                self.errorMessage = "加载音频失败: \(error.displayMessage)"
            }
        }
    }

    private func setupPlayer(with urlString: String) {
        let directive = SourceURLDirectiveParser().parse(urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let url = URL(string: directive.urlText) else {
            isLoading = false
            errorMessage = "音频链接无效，请刷新章节或更换书源"
            return
        }
        self.currentAudioURL = urlString

        var headers: [String: String] = [:]
        if let source = currentSource {
            headers = SourceRequestBuilder().imageRequestHeaders(for: source, chapterURL: currentChapter?.url)
            headers["Accept"] = "*/*"
        }
        for (key, value) in directive.headers { headers[key] = value }
        let assetOptions: [String: Any]? = headers.isEmpty
            ? nil
            : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: assetOptions)
        let item = AVPlayerItem(asset: asset)
        let loadID = chapterLoadID

        chapterEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.chapterLoadID == loadID, self.player?.currentItem === item else { return }
                if self.stopAtChapterEnd {
                    self.pause()
                    self.stopAtChapterEnd = false
                    self.sleepTimerMinutesRemaining = nil
                } else {
                    self.playNextChapter()
                }
            }
        }

        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.chapterLoadID == loadID, self.player?.currentItem === item else { return }
                if item.status == .failed {
                    self.pause()
                    self.isLoading = false
                    self.errorMessage = "音频无法播放，请重试或更换书源"
                } else if item.status == .readyToPlay {
                    self.isLoading = false
                    self.updateDuration(from: item)
                }
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, self.chapterLoadID == loadID, self.player?.currentItem === item else { return }
            self.currentTime = time.seconds.isFinite ? max(0, time.seconds) : 0
            self.updateDuration(from: item)
            self.persistProgressIfNeeded()
            self.updateNowPlayingInfo()
        }

        if shouldPlayWhenReady { play() }
        updateNowPlayingInfo()
    }

    private func updateDuration(from item: AVPlayerItem) {
        guard item.duration.isNumeric, item.duration.seconds.isFinite, item.duration.seconds > 0 else { return }
        duration = item.duration.seconds
        if let pending = pendingResumeSeconds {
            pendingResumeSeconds = nil
            if pending < duration { seek(to: pending) }
        }
    }

    private func releasePlayer() {
        seekID = UUID()
        isSeeking = false
        fadeTimer?.invalidate()
        fadeTimer = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let chapterEndObserver { NotificationCenter.default.removeObserver(chapterEndObserver) }
        chapterEndObserver = nil
        if let token = timeObserverToken { player?.removeTimeObserver(token) }
        timeObserverToken = nil
        player?.pause()
        player = nil
        isPlaying = false
        currentAudioURL = nil
        currentTime = 0
        duration = 0
    }

    private func persistProgressIfNeeded(force: Bool = false) {
        guard player != nil, pendingResumeSeconds == nil, !isSeeking,
              let bookID = currentBookID, let bookshelfStore,
              currentTime.isFinite, currentTime >= 0, currentTime < Double(Int.max) else { return }
        let currentSec = Int(currentTime)
        guard force || abs(currentSec - lastPersistedSecond) >= 3 else { return }
        lastPersistedSecond = currentSec
        bookshelfStore.updateReadingProgress(
            bookID: bookID,
            chapterIndex: currentChapterIndex,
            chapterTitle: currentChapter?.title,
            totalChapters: max(chapters.count, currentChapterIndex + 1),
            paragraphIndex: currentSec
        )
    }

    func play() {
        guard let player, player.currentItem?.status != .failed else {
            isPlaying = false
            return
        }
        shouldPlayWhenReady = true
        fadeTimer?.invalidate()
        fadeTimer = nil
        player.volume = 1.0
        player.play()
        player.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        shouldPlayWhenReady = false
        fadeTimer?.invalidate()
        fadeTimer = nil
        player?.pause()
        isPlaying = false
        persistProgressIfNeeded(force: true)
        updateNowPlayingInfo()
    }

    func fadeOutAndPause(duration: TimeInterval = 8.0, completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        guard duration.isFinite, duration > 0, let player = self.player, isPlaying, isFadeOutEnabled else {
            self.pause()
            completion?()
            return
        }

        let initialVolume = player.volume
        let loadID = chapterLoadID
        let steps = 16
        let interval = duration / Double(steps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self, self.chapterLoadID == loadID, let player = self.player else {
                    timer.invalidate()
                    return
                }
                currentStep += 1
                let progress = Float(currentStep) / Float(steps)
                player.volume = max(0, initialVolume * (1.0 - progress))
                if currentStep >= steps {
                    timer.invalidate()
                    self.fadeTimer = nil
                    self.pause()
                    player.volume = initialVolume
                    completion?()
                }
            }
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        persistProgressIfNeeded(force: true)
        chapterLoadID = UUID()
        chapterLoadTask?.cancel()
        chapterLoadTask = nil
        releasePlayer()
        artworkLoadID = UUID()
        artworkTask?.cancel()
        artworkTask = nil
        currentArtwork = nil
        currentEngine = nil
        chapters = []
        currentChapterIndex = 0
        isLoading = false
        errorMessage = nil
        shouldPlayWhenReady = false
        shouldResumeAfterInterruption = false
        currentBook = nil
        currentSource = nil
        currentAudioURL = nil
        currentBookID = nil
        bookshelfStore = nil
        pendingResumeSeconds = nil
        lastPersistedSecond = 0
        currentTime = 0
        duration = 0
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerMinutesRemaining = nil
        stopAtChapterEnd = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, duration.isFinite, duration > 0, let player else { return }
        let loadID = chapterLoadID
        seekID = UUID()
        let requestID = seekID
        isSeeking = true
        let targetTime = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.chapterLoadID == loadID, self.seekID == requestID else { return }
                self.isSeeking = false
                guard finished else { return }
                self.currentTime = targetTime.seconds
                self.persistProgressIfNeeded(force: true)
                self.updateNowPlayingInfo()
            }
        }
    }

    func skip(seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func playNextChapter() {
        guard currentChapterIndex + 1 < chapters.count else {
            pause()
            return
        }
        playChapter(at: currentChapterIndex + 1)
    }

    func playPreviousChapter() {
        if currentTime > 3.0 {
            seek(to: 0)
        } else if currentChapterIndex > 0 {
            playChapter(at: currentChapterIndex - 1)
        }
    }

    func setPlaybackRate(_ rate: Float) {
        guard rate.isFinite else { return }
        playbackRate = min(max(rate, 0.5), 3)
        if isPlaying {
            player?.rate = playbackRate
        }
        updateNowPlayingInfo()
    }

    // MARK: - Sleep Timer

    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        stopAtChapterEnd = false

        guard let minutes, minutes >= 0 else {
            sleepTimerMinutesRemaining = nil
            return
        }

        if minutes == 0 {
            // End of current chapter
            stopAtChapterEnd = true
            sleepTimerMinutesRemaining = nil
            return
        }

        sleepTimerMinutesRemaining = minutes
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let current = self.sleepTimerMinutesRemaining else {
                    timer.invalidate()
                    return
                }
                if current <= 1 {
                    self.sleepTimerMinutesRemaining = nil
                    timer.invalidate()
                    self.sleepTimer = nil
                    if self.isFadeOutEnabled {
                        self.fadeOutAndPause(duration: 8.0)
                    } else {
                        self.pause()
                    }
                } else {
                    self.sleepTimerMinutesRemaining = current - 1
                }
            }
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let chapter = currentChapter else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapter.title,
            MPMediaItemPropertyAlbumTitle: currentBook?.name ?? "有声书",
            MPMediaItemPropertyArtist: currentBook?.author ?? currentSource?.bookSourceName ?? "源阅读",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : 0.0
        ]

        if let artwork = currentArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadCoverArtwork(url: String?) {
        artworkTask?.cancel()
        artworkLoadID = UUID()
        let loadID = artworkLoadID
        currentArtwork = nil
        guard let urlString = url, let coverURL = URL(string: urlString) else { return }
        artworkTask = Task { @MainActor [weak self] in
            guard let image = await RemoteImageLoader.shared.image(for: coverURL, maxPixelSize: 512, reuseCoverBytes: true),
                  !Task.isCancelled, let self, self.artworkLoadID == loadID else { return }
            self.currentArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlayingInfo()
            self.artworkTask = nil
        }
    }

    // MARK: - Helpers

}
