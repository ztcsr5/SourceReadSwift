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

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var sleepTimer: Timer?
    private var currentArtwork: MPMediaItemArtwork?
    private var currentEngine: SourceEngine?
    private var currentBookID: String?
    private var pendingResumeSeconds: Double?
    private var bookshelfStore: BookshelfStore?
    private var lastPersistedSecond: Int = 0

    var currentChapter: BookChapter? {
        guard chapters.indices.contains(currentChapterIndex) else { return nil }
        return chapters[currentChapterIndex]
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
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
        NotificationCenter.default.removeObserver(self)
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
        NotificationCenter.default.addObserver(
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
                self.pause()
            } else if type == .ended {
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
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
        self.currentBookID = bookID
        self.currentBook = book
        self.currentSource = source
        self.chapters = chapters
        self.currentEngine = engine
        self.bookshelfStore = bookshelfStore
        self.pendingResumeSeconds = initialPositionSeconds
        self.currentChapterIndex = max(0, min(initialChapterIndex, chapters.count - 1))
        loadCoverArtwork(url: book.coverUrl)
        playChapter(at: self.currentChapterIndex)
    }

    func playChapter(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentChapterIndex = index
        let chapter = chapters[index]
        isLoading = true
        errorMessage = nil

        // If audio url is already known in chapter url or content
        if let directURL = extractAudioURL(from: chapter.url), isAudioMediaURL(directURL) {
            setupPlayer(with: directURL)
            return
        }

        // Fetch chapter content from engine to obtain streaming audio link
        guard let source = currentSource, let engine = currentEngine else {
            isLoading = false
            errorMessage = "缺少书源引擎"
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let contentResult = await engine.getContent(source: source, chapter: chapter)
            switch contentResult {
            case .success(let content):
                if let audioURL = self.extractAudioURL(from: content.text) ?? self.extractAudioURL(from: chapter.url) {
                    self.setupPlayer(with: audioURL)
                } else if !content.text.isEmpty {
                    self.setupPlayer(with: content.text.trimmingCharacters(in: .whitespacesAndNewlines))
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
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            isLoading = false
            errorMessage = "无效的音频链接: \(urlString)"
            return
        }
        self.currentAudioURL = urlString

        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
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
        newPlayer.rate = playbackRate
        self.player = newPlayer

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            if let currentItem = self.player?.currentItem, currentItem.duration.isNumeric {
                self.duration = currentItem.duration.seconds
                self.isLoading = false

                if let pending = self.pendingResumeSeconds, pending > 0, pending < self.duration {
                    self.seek(to: pending)
                    self.pendingResumeSeconds = nil
                }
            }
            self.persistProgressIfNeeded()
            self.updateNowPlayingInfo()
        }

        newPlayer.play()
        newPlayer.rate = playbackRate
        isPlaying = true
        isLoading = false
        updateNowPlayingInfo()
    }

    private func persistProgressIfNeeded() {
        guard let bookID = currentBookID, let bookshelfStore else { return }
        let currentSec = Int(currentTime)
        guard abs(currentSec - lastPersistedSecond) >= 3 else { return }
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
        player?.play()
        player?.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        persistProgressIfNeeded()
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        pause()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player = nil
        currentBook = nil
        currentSource = nil
        currentAudioURL = nil
        currentTime = 0
        duration = 0
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerMinutesRemaining = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to seconds: Double) {
        let targetTime = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateNowPlayingInfo()
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
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlayingInfo()
    }

    // MARK: - Sleep Timer

    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        stopAtChapterEnd = false

        guard let minutes else {
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
                    self.pause()
                    self.sleepTimerMinutesRemaining = nil
                    timer.invalidate()
                    self.sleepTimer = nil
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
        guard let urlString = url, let coverURL = URL(string: urlString) else { return }
        Task.detached(priority: .background) {
            guard let data = try? Data(contentsOf: coverURL), let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            Task { @MainActor [weak self] in
                self?.currentArtwork = artwork
                self?.updateNowPlayingInfo()
            }
        }
    }

    // MARK: - Helpers

    private func extractAudioURL(from text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }

        // Look for audio extensions
        let audioExtensions = [".mp3", ".m4a", ".aac", ".ogg", ".wav", ".flac"]
        for ext in audioExtensions {
            if let range = text.range(of: ext, options: .caseInsensitive) {
                // Find preceding http:// or https://
                let prefix = text[..<range.upperBound]
                if let httpIdx = prefix.range(of: "http", options: [.backwards, .caseInsensitive])?.lowerBound {
                    let candidate = String(text[httpIdx..<range.upperBound])
                    if URL(string: candidate) != nil {
                        return candidate
                    }
                }
            }
        }

        // Look for HTML <source src="..."> or <audio src="...">
        if let srcRange = text.range(of: "src=\"", options: .caseInsensitive) {
            let rest = text[srcRange.upperBound...]
            if let quoteRange = rest.range(of: "\"") {
                let candidate = String(rest[..<quoteRange.lowerBound])
                if candidate.hasPrefix("http") {
                    return candidate
                }
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }

        return nil
    }

    private func isAudioMediaURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasSuffix(".mp3") || lower.hasSuffix(".m4a") || lower.hasSuffix(".aac") || lower.hasSuffix(".wav") || lower.hasSuffix(".ogg") || lower.hasSuffix(".flac") || lower.contains(".mp3?") || lower.contains(".m4a?")
    }
}
