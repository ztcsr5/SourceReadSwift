import AVFoundation

/// Plays MP3 data returned by the cloud TTS client. Kept as a plain NSObject
/// (not @MainActor) so ReaderSpeechController can own it without changing the
/// existing AVSpeechSynthesizer delegate isolation.
final class CloudTTSPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    var onFinish: (() -> Void)?
    var onError: ((Error) -> Void)?

    var isPlaying: Bool {
        player?.isPlaying == true
    }

    func play(data: Data) throws {
        stop()
        try activateSession()
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            throw XunfeiTTSError.playbackUnavailable
        }
        self.player = player
    }

    /// 播本地导入的音频文件（`.file` 朗读通道）。和 `play(data:)` 共用同一个
    /// AVAudioPlayer 实例与回调，因此暂停/继续/停止/跨段推进的语义完全一致。
    func play(fileURL: URL) throws {
        stop()
        try activateSession()
        let player = try AVAudioPlayer(contentsOf: fileURL)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else {
            throw XunfeiTTSError.playbackUnavailable
        }
        self.player = player
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: [])
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        if flag {
            onFinish?()
        } else {
            onError?(XunfeiTTSError.playbackUnavailable)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.player = nil
        onError?(error ?? XunfeiTTSError.playbackUnavailable)
    }
}
