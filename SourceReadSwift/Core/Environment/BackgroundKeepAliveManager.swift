import Foundation
import AVFoundation
import UIKit

/// Manages background execution and process keepalive.
///
/// Ensures long-running operations (such as batch source health diagnostics,
/// bulk book downloads, and catalog syncing) continue uninterrupted when
/// the app transitions to the background, when the screen locks, or when
/// running inside sandboxed environments like LiveContainer, AltStore, or TrollStore.
///
/// Employs a dual-tier strategy:
/// 1. Silent audio playback (`AVAudioSession` in `.playback` mode with `.mixWithOthers`),
///    which keeps the audio unit active in the background without interrupting
///    user music, podcasts, or system sounds.
/// 2. Self-renewing `UIBackgroundTaskIdentifier` chain that prevents abrupt
///    suspension by iOS watchdog timers.
@MainActor
final class BackgroundKeepAliveManager: NSObject, AVAudioPlayerDelegate {
    static let shared = BackgroundKeepAliveManager()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentReason: String = ""

    private var audioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var renewalTimer: Timer?
    private var referenceCount: Int = 0

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Starts or retains background keepalive for the specified reason.
    func start(reason: String = "Background Processing") {
        referenceCount += 1
        currentReason = reason

        guard !isActive else { return }
        isActive = true

        setupAudioSession()
        startSilentAudio()
        beginBackgroundTaskChain()
    }

    /// Releases a retain on background keepalive, stopping when count hits zero.
    func stop(force: Bool = false) {
        if force {
            referenceCount = 0
        } else {
            referenceCount = max(0, referenceCount - 1)
        }

        guard referenceCount == 0 else { return }
        guard isActive else { return }

        isActive = false
        currentReason = ""

        stopSilentAudio()
        tearDownAudioSession()
        endBackgroundTaskChain()
    }

    // MARK: - Audio Keepalive

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio session setup is best-effort; task identifier continues as fallback
        }
    }

    private func tearDownAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Best effort teardown
        }
    }

    private func startSilentAudio() {
        guard audioPlayer == nil else {
            if audioPlayer?.isPlaying == false {
                audioPlayer?.play()
            }
            return
        }

        let silentWav = Self.generateSilentWAVData(durationSeconds: 1.0)
        do {
            let player = try AVAudioPlayer(data: silentWav)
            player.delegate = self
            player.numberOfLoops = -1 // Infinite loop
            player.volume = 0.0 // True silence
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
        } catch {
            // Fall back to pure background task assertion
        }
    }

    private func stopSilentAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - Background Task Identifier Chain

    private func beginBackgroundTaskChain() {
        endBackgroundTaskChain()
        renewBackgroundTask()

        // Monitor background time and rotate task identifier periodically
        renewalTimer?.invalidate()
        renewalTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndRenewBackgroundTask()
            }
        }
    }

    private func renewBackgroundTask() {
        let oldTaskID = backgroundTaskID
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BackgroundKeepAlive.\(currentReason)") { [weak self] in
            Task { @MainActor [weak self] in
                // Emergency expiration callback from iOS
                self?.renewBackgroundTask()
            }
        }

        if oldTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(oldTaskID)
        }
    }

    private func checkAndRenewBackgroundTask() {
        guard isActive else { return }
        let remaining = UIApplication.shared.backgroundTimeRemaining
        // If remaining time drops below 10 seconds or is indefinite, renew
        if remaining < 10.0 && remaining > 0.0 {
            renewBackgroundTask()
        }
        // Ensure audio player is still playing
        if audioPlayer?.isPlaying == false {
            audioPlayer?.play()
        }
    }

    private func endBackgroundTaskChain() {
        renewalTimer?.invalidate()
        renewalTimer = nil

        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    // MARK: - Silent WAV Generator

    /// Generates a valid, minimal standard RIFF WAV file with 0-amplitude PCM samples.
    private static func generateSilentWAVData(durationSeconds: Double = 1.0) -> Data {
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let numSamples = Int(Double(sampleRate) * durationSeconds)
        let subchunk2Size = Int32(numSamples * Int(channels) * Int(bitsPerSample / 8))
        let chunkSize = 36 + subchunk2Size
        let byteRate = Int32(sampleRate * Int32(channels) * Int32(bitsPerSample / 8))
        let blockAlign = Int16(channels * (bitsPerSample / 8))

        var data = Data()
        data.reserveCapacity(44 + Int(subchunk2Size))

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // "fmt " subchunk
        data.append(contentsOf: "fmt ".utf8)
        let subchunk1Size: Int32 = 16
        data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
        let audioFormat: Int16 = 1 // PCM
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // "data" subchunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: subchunk2Size.littleEndian) { Array($0) })

        // Silent audio samples (all zeros)
        data.append(Data(repeating: 0, count: Int(subchunk2Size)))

        return data
    }
}
