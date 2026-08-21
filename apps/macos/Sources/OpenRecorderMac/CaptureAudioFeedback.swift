import AVFoundation
import AppKit

// MARK: - CaptureAudioFeedback

/// Plays synthesised audio feedback sounds for mouse clicks and keyboard keystrokes
/// while a screen recording is in progress.
///
/// Both sound types are generated on-the-fly as raw PCM WAV data — no bundled
/// audio assets are required. A shared AVAudioPlayer pool keeps the last
/// queued sound hot so rapid-fire triggers never drop frames or block the main thread.
@MainActor
final class CaptureAudioFeedback {
    static let shared = CaptureAudioFeedback()

    // MARK: Public toggles (read from RecordingPreferencesStore)

    var mouseClickSoundsEnabled: Bool = false
    var keyboardSoundsEnabled: Bool = false

    // MARK: Private state

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    private let clickSoundData: Data?
    private let keystrokeSoundData: Data?

    private var clickPlayers: [AVAudioPlayer] = []
    private let clickPoolSize = 4
    private var clickPoolIndex = 0

    private var keystrokePlayers: [AVAudioPlayer] = []
    private let keystrokePoolSize = 6
    private var keystrokePoolIndex = 0

    // MARK: - Init

    init() {
        clickSoundData = CaptureAudioFeedback.generateClickWAV()
        keystrokeSoundData = CaptureAudioFeedback.generateKeystrokeWAV()
        preparePlayers()
    }

    // MARK: - Public API

    func startMonitoring() {
        guard mouseClickSoundsEnabled || keyboardSoundsEnabled else { return }
        installMonitors()
    }

    func stopMonitoring() {
        removeMonitors()
    }

    func refreshMonitors() {
        removeMonitors()
        if mouseClickSoundsEnabled || keyboardSoundsEnabled {
            installMonitors()
        }
    }

    // MARK: - Monitor installation

    private func installMonitors() {
        if mouseClickSoundsEnabled {
            let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] _ in
                Task { @MainActor [weak self] in self?.playClick() }
            }
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
                Task { @MainActor [weak self] in self?.playClick() }
                return event
            }
        }

        if keyboardSoundsEnabled {
            let keyMask: NSEvent.EventTypeMask = [.keyDown]
            globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] _ in
                Task { @MainActor [weak self] in self?.playKeystroke() }
            }
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
                Task { @MainActor [weak self] in self?.playKeystroke() }
                return event
            }
        }
    }

    private func removeMonitors() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        if let m = localMouseMonitor  { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        if let m = globalKeyMonitor   { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = localKeyMonitor    { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }

    // MARK: - Playback helpers

    private func playClick() {
        guard mouseClickSoundsEnabled, !clickPlayers.isEmpty else { return }
        let player = clickPlayers[clickPoolIndex % clickPlayers.count]
        clickPoolIndex = (clickPoolIndex + 1) % clickPlayers.count
        player.currentTime = 0
        player.play()
    }

    private func playKeystroke() {
        guard keyboardSoundsEnabled, !keystrokePlayers.isEmpty else { return }
        let player = keystrokePlayers[keystrokePoolIndex % keystrokePlayers.count]
        keystrokePoolIndex = (keystrokePoolIndex + 1) % keystrokePlayers.count
        player.currentTime = 0
        player.play()
    }

    // MARK: - Player preparation

    private func preparePlayers() {
        if let data = clickSoundData {
            for _ in 0..<clickPoolSize {
                if let p = try? AVAudioPlayer(data: data) {
                    p.prepareToPlay()
                    p.volume = 0.52
                    clickPlayers.append(p)
                }
            }
        }
        if let data = keystrokeSoundData {
            for _ in 0..<keystrokePoolSize {
                if let p = try? AVAudioPlayer(data: data) {
                    p.prepareToPlay()
                    p.volume = 0.38
                    keystrokePlayers.append(p)
                }
            }
        }
    }

    // MARK: - Sound synthesis

    /// Synthesises a short, satisfying mouse-click sound:
    /// a percussive transient pop with fast attack and exponential decay.
    private static func generateClickWAV() -> Data? {
        let sampleRate: Double = 44100
        let duration: Double = 0.065
        let total = Int(sampleRate * duration)
        var samples = [Int16](repeating: 0, count: total)

        for i in 0..<total {
            let t = Double(i) / sampleRate
            let freq = 220.0 * (1 + max(0, 0.12 * (1 - t / 0.006)))
            let wave = sin(2 * .pi * freq * t) * 0.68
                     + sin(2 * .pi * freq * 2 * t) * 0.22
                     + sin(2 * .pi * freq * 3 * t) * 0.10
            let attack = min(1.0, t / 0.0015)
            let decay  = max(0.0, 1.0 - (t / duration))
            let env    = attack * pow(decay, 2.8)
            let value  = wave * env * 0.55
            samples[i] = Int16(max(-32767, min(32767, value * 32767)))
        }
        return makeWAV(samples: samples, sampleRate: Int32(sampleRate))
    }

    /// Synthesises a soft keyboard keystroke sound:
    /// a very brief high-frequency tap with near-instant decay.
    private static func generateKeystrokeWAV() -> Data? {
        let sampleRate: Double = 44100
        let duration: Double = 0.045
        let total = Int(sampleRate * duration)
        var samples = [Int16](repeating: 0, count: total)

        for i in 0..<total {
            let t = Double(i) / sampleRate
            let freq = 480.0 * (1 + max(0, 0.06 * (1 - t / 0.004)))
            let wave = sin(2 * .pi * freq * t) * 0.60
                     + sin(2 * .pi * freq * 2 * t) * 0.28
                     + sin(2 * .pi * freq * 3 * t) * 0.12
            let attack = min(1.0, t / 0.001)
            let decay  = max(0.0, 1.0 - (t / duration))
            let env    = attack * pow(decay, 3.5)
            let value  = wave * env * 0.42
            samples[i] = Int16(max(-32767, min(32767, value * 32767)))
        }
        return makeWAV(samples: samples, sampleRate: Int32(sampleRate))
    }

    // MARK: - WAV builder

    private static func makeWAV(samples: [Int16], sampleRate: Int32) -> Data {
        var data = Data()
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = sampleRate * Int32(numChannels * bitsPerSample / 8)
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = Int32(samples.count * MemoryLayout<Int16>.size)
        let chunkSize = 36 + dataSize

        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        return data
    }
}
