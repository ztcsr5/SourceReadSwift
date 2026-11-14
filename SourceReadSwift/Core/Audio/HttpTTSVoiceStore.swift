import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI
import UIKit

/// Persists user-created and imported Legado `httpTTS.json` speech voices.
enum HttpTTSVoiceStore {
    private static let fileName = "httpTTS_voices.json"

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("SourceReadSwift", isDirectory: true)
    }

    static func fileURL(in directory: URL = defaultDirectory) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func loadCustomVoices(from directory: URL = defaultDirectory) -> [HttpTTSVoice] {
        let url = fileURL(in: directory)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? parseLegadoJSON(data)) ?? []
    }

    static func saveCustomVoices(_ voices: [HttpTTSVoice], to directory: URL = defaultDirectory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try exportJSON(voices)
        try data.write(to: fileURL(in: directory), options: .atomic)
    }

    static func allVoices(from directory: URL = defaultDirectory) -> [HttpTTSVoice] {
        let custom = loadCustomVoices(from: directory)
        let customIDs = Set(custom.map(\.id))
        return custom + HttpTTSVoice.defaultVoices.filter { !customIDs.contains($0.id) }
    }

    static func voice(id: Int, in directory: URL = defaultDirectory) -> HttpTTSVoice? {
        allVoices(from: directory).first(where: { $0.id == id })
            ?? allVoices(from: directory).first
    }

    @discardableResult
    static func upsert(_ voice: HttpTTSVoice, in directory: URL = defaultDirectory) throws -> [HttpTTSVoice] {
        var existing = loadCustomVoices(from: directory)
        if let index = existing.firstIndex(where: { $0.id == voice.id }) {
            existing[index] = voice
        } else {
            existing.insert(voice, at: 0)
        }
        try saveCustomVoices(existing, to: directory)
        return existing
    }

    @discardableResult
    static func importJSON(_ data: Data, into directory: URL = defaultDirectory) throws -> (added: Int, voices: [HttpTTSVoice]) {
        let parsed = try parseLegadoJSON(data)
        var existing = loadCustomVoices(from: directory)
        var added = 0
        for item in parsed {
            if let idx = existing.firstIndex(where: { $0.id == item.id }) {
                existing[idx] = item
            } else {
                existing.append(item)
                added += 1
            }
        }
        try saveCustomVoices(existing, to: directory)
        return (added, existing)
    }

    @discardableResult
    static func remove(id: Int, from directory: URL = defaultDirectory) throws -> [HttpTTSVoice] {
        var existing = loadCustomVoices(from: directory)
        existing.removeAll(where: { $0.id == id })
        try saveCustomVoices(existing, to: directory)
        return existing
    }

    static func makeNewVoiceID(existing: [HttpTTSVoice]) -> Int {
        let used = Set(existing.map(\.id) + HttpTTSVoice.defaultVoices.map(\.id))
        var candidate = max(10_000, Int(Date().timeIntervalSince1970) % 1_000_000)
        while used.contains(candidate) {
            candidate += 1
        }
        return candidate
    }

    static func parseLegadoJSON(_ data: Data) throws -> [HttpTTSVoice] {
        let decoder = JSONDecoder()
        let decoded: [HttpTTSVoice]
        if let array = try? decoder.decode([HttpTTSVoice].self, from: data) {
            decoded = array
        } else {
            let single = try decoder.decode(HttpTTSVoice.self, from: data)
            decoded = [single]
        }
        let valid = decoded.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !valid.isEmpty else {
            throw HttpTTSError.server("httpTTS.json 中没有有效发音人模板")
        }
        return valid
    }

    static func exportJSON(_ voices: [HttpTTSVoice]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(voices)
    }
}

/// Pure policy determining whether hardware volume keys should turn pages.
enum ReaderVolumeTurnPolicy {
    static func shouldIntercept(
        isEnabled: Bool,
        isSpeaking: Bool,
        isSheetPresented: Bool,
        isActive: Bool
    ) -> Bool {
        isEnabled && !isSpeaking && !isSheetPresented && isActive
    }
}

/// Hidden `MPVolumeView` + KVO bridge capturing hardware volume key presses
/// for page turns while yielding cleanly when TTS or modals are active.
struct ReaderVolumeKeyListener: UIViewRepresentable {
    let isActive: Bool
    let onStep: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStep: onStep)
    }

    func makeUIView(context: Context) -> VolumeCaptureHostView {
        let view = VolumeCaptureHostView()
        context.coordinator.bind(host: view)
        context.coordinator.setActive(isActive)
        return view
    }

    func updateUIView(_ uiView: VolumeCaptureHostView, context: Context) {
        context.coordinator.onStep = onStep
        context.coordinator.setActive(isActive)
    }

    static func dismantleUIView(_ uiView: VolumeCaptureHostView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class VolumeCaptureHostView: UIView {
        let volumeView: MPVolumeView = {
            let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
            view.alpha = 0.001
            view.isUserInteractionEnabled = false
            return view
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            clipsToBounds = true
            addSubview(volumeView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    final class Coordinator: NSObject {
        var onStep: (Int) -> Void
        private weak var host: VolumeCaptureHostView?
        private var volumeObservation: NSKeyValueObservation?
        private var baselineVolume: Float = 0.5
        private var isActive = false
        private var lastHandledAt: CFTimeInterval = 0
        private var ignoringCallback = false

        init(onStep: @escaping (Int) -> Void) {
            self.onStep = onStep
        }

        deinit {
            teardown()
        }

        func bind(host: VolumeCaptureHostView) {
            self.host = host
        }

        func setActive(_ active: Bool) {
            guard active != isActive else { return }
            isActive = active
            if active {
                startObserving()
            } else {
                stopObserving()
            }
        }

        private func startObserving() {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true, options: [])
            let initial = session.outputVolume
            baselineVolume = min(max(initial, 0.15), 0.85)
            setSliderVolume(baselineVolume)
            volumeObservation = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, change in
                guard let self, self.isActive else { return }
                guard let newVal = change.newValue else { return }
                Task { @MainActor [weak self] in
                    self?.handleVolumeChange(newValue: newVal)
                }
            }
        }

        private func stopObserving() {
            volumeObservation?.invalidate()
            volumeObservation = nil
        }

        func teardown() {
            isActive = false
            stopObserving()
        }

        @MainActor
        private func handleVolumeChange(newValue: Float) {
            guard isActive, !ignoringCallback else { return }
            let delta = newValue - baselineVolume
            guard abs(delta) >= 0.005 else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastHandledAt >= 0.14 else {
                resetToBaseline()
                return
            }
            lastHandledAt = now
            // Volume down (< 0) flips forward; volume up (> 0) flips backward.
            let direction = delta < 0 ? 1 : -1
            resetToBaseline()
            onStep(direction)
        }

        @MainActor
        private func resetToBaseline() {
            ignoringCallback = true
            setSliderVolume(baselineVolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.ignoringCallback = false
            }
        }

        private func setSliderVolume(_ value: Float) {
            guard let host else { return }
            if let slider = host.volumeView.subviews.compactMap({ $0 as? UISlider }).first {
                DispatchQueue.main.async {
                    slider.value = value
                }
            }
        }
    }
}

/// Theme-matched lightweight procedural white-noise / ambient soundscape engine
/// requiring zero large audio asset bundles.
enum ReaderAmbientPreset: String, CaseIterable, Identifiable, Sendable {
    case auto
    case rain
    case paperWind
    case nightWave
    case cafeWarmth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "随主题匹配"
        case .rain: return "竹窗夜雨"
        case .paperWind: return "松风墨韵"
        case .nightWave: return "月下星潮"
        case .cafeWarmth: return "暖炉书斋"
        }
    }

    var systemImage: String {
        switch self {
        case .auto: return "sparkles"
        case .rain: return "cloud.rain"
        case .paperWind: return "wind"
        case .nightWave: return "water.waves"
        case .cafeWarmth: return "flame"
        }
    }

    static func recommended(for visualTheme: AppVisualTheme) -> ReaderAmbientPreset {
        switch visualTheme {
        case .wuxia, .forest: return .rain
        case .shuimo, .classic: return .paperWind
        case .anime, .kleinSage: return .nightWave
        case .kawaii, .custom: return .cafeWarmth
        }
    }

    /// Low-pass coefficient & soft gain tailored to each soundscape.
    var filterParameters: (alpha: Float, gain: Float) {
        switch self {
        case .auto: return (0.045, 0.22)
        case .rain: return (0.068, 0.24)
        case .paperWind: return (0.032, 0.20)
        case .nightWave: return (0.024, 0.24)
        case .cafeWarmth: return (0.048, 0.22)
        }
    }
}

@MainActor
final class ReaderAmbientSoundscapeEngine: ObservableObject {
    static let shared = ReaderAmbientSoundscapeEngine()

    @Published private(set) var isPlaying = false
    @Published private(set) var activePreset: ReaderAmbientPreset = .rain
    @Published var timerRemainingSeconds: Int? = nil

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var countdownTask: Task<Void, Never>?
    private var volumeGain: Float = 0.35

    private init() {}

    func start(
        preset: ReaderAmbientPreset,
        visualTheme: AppVisualTheme,
        volume: Double,
        timerMinutes: Int = 0
    ) {
        let resolved = preset == .auto ? ReaderAmbientPreset.recommended(for: visualTheme) : preset
        activePreset = resolved
        volumeGain = Float(min(max(volume, 0.02), 0.9))

        stopEngineOnly()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])

        let audioEngine = AVAudioEngine()
        let format = audioEngine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 44100
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            ?? audioEngine.mainMixerNode.outputFormat(forBus: 0)

        let params = resolved.filterParameters
        var lpState: Float = 0
        var modPhase: Float = 0
        var seed: UInt64 = 0x5EED_CAFE_1337
        let sr = Float(outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44100)
        let modFreq: Float = resolved == .nightWave ? 0.12 : (resolved == .paperWind ? 0.18 : 0.25)

        let node = AVAudioSourceNode(format: outputFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let userGain = self?.volumeGain ?? 0.35
            for frame in 0..<Int(frameCount) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let white = Float(Int32(bitPattern: UInt32(truncatingIfNeeded: seed >> 32))) / Float(Int32.max)
                lpState = lpState + params.alpha * (white - lpState)
                modPhase += (2.0 * Float.pi * modFreq) / sr
                if modPhase > 2.0 * Float.pi { modPhase -= 2.0 * Float.pi }
                let swell = 0.82 + 0.18 * sinf(modPhase)
                let sample = lpState * params.gain * userGain * swell
                for buf in buffers {
                    if let ptr = buf.mData?.assumingMemoryBound(to: Float.self) {
                        ptr[frame] = sample
                    }
                }
            }
            return noErr
        }

        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: outputFormat)
        do {
            try audioEngine.start()
            engine = audioEngine
            sourceNode = node
            isPlaying = true
            configureTimer(minutes: timerMinutes)
        } catch {
            stop()
        }
    }

    func updateVolume(_ volume: Double) {
        volumeGain = Float(min(max(volume, 0.02), 0.9))
    }

    func configureTimer(minutes: Int) {
        countdownTask?.cancel()
        countdownTask = nil
        guard isPlaying, minutes > 0 else {
            timerRemainingSeconds = nil
            return
        }
        timerRemainingSeconds = minutes * 60
        countdownTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                if let rem = self.timerRemainingSeconds {
                    if rem <= 1 {
                        self.stop()
                        return
                    }
                    self.timerRemainingSeconds = rem - 1
                }
            }
        }
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        timerRemainingSeconds = nil
        stopEngineOnly()
        isPlaying = false
    }

    private func stopEngineOnly() {
        engine?.stop()
        if let node = sourceNode {
            engine?.detach(node)
        }
        sourceNode = nil
        engine = nil
    }
}
