import AVFoundation
import AppKit

@MainActor
final class RecordingSoundEffects {
    static let shared = RecordingSoundEffects()

    private var countdownPlayers: [Int: AVAudioPlayer] = [:]
    private var startRecordingPlayer: AVAudioPlayer?

    init() {
        preparePlayers()
    }

    func playCountdownTick(for count: Int = 3) {
        if let player = countdownPlayers[count] ?? countdownPlayers[3] {
            player.currentTime = 0
            player.play()
        } else {
            NSSound(named: "Tink")?.play()
        }
    }

    func playRecordingStarted() {
        if let startRecordingPlayer {
            startRecordingPlayer.currentTime = 0
            startRecordingPlayer.play()
        } else {
            NSSound(named: "Ping")?.play()
        }
    }

    private func preparePlayers() {
        // Ascending harmonic notes for countdown: 3 (C5), 2 (E5), 1 (G5)
        let countdownNotes: [Int: Double] = [
            3: 523.25, // C5
            2: 659.25, // E5
            1: 783.99  // G5
        ]

        for (count, freq) in countdownNotes {
            if let wavData = generateTactilePopWAV(baseFrequency: freq) {
                if let player = try? AVAudioPlayer(data: wavData) {
                    player.prepareToPlay()
                    countdownPlayers[count] = player
                }
            }
        }

        if let startWav = generateStudioChimeWAV() {
            startRecordingPlayer = try? AVAudioPlayer(data: startWav)
            startRecordingPlayer?.prepareToPlay()
        }
    }

    /// Generates a warm, organic tactile UI pop with harmonic richness and subtle attack transient
    private func generateTactilePopWAV(baseFrequency: Double) -> Data? {
        let sampleRate: Double = 44100
        let duration: Double = 0.10
        let totalSamples = Int(sampleRate * duration)

        var samples = [Int16](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / sampleRate

            // Micro pitch-drop at transient onset for acoustic "thump" realism
            let pitchBend = 1.0 + max(0.0, 0.08 * (1.0 - t / 0.02))
            let currentFreq = baseFrequency * pitchBend

            // Harmonic layering: Fundamental (65%) + Octave (25%) + 3rd Harmonic (10%)
            let wave1 = sin(2.0 * .pi * currentFreq * t) * 0.65
            let wave2 = sin(2.0 * .pi * (currentFreq * 2.0) * t) * 0.25
            let wave3 = sin(2.0 * .pi * (currentFreq * 3.0) * t) * 0.10
            let rawWave = wave1 + wave2 + wave3

            // Acoustic envelope: Ultra-fast 2ms attack, smooth exponential decay
            let attack = min(1.0, t / 0.0025)
            let decay = max(0.0, 1.0 - (t / duration))
            let envelope = attack * pow(decay, 2.2)

            let sample = rawWave * envelope * 0.45
            samples[i] = Int16(max(-32767, min(32767, sample * 32767.0)))
        }

        return createWAVData(samples: samples, sampleRate: Int32(sampleRate))
    }

    /// Generates an uplifting, lush studio chime with arpeggiated C6-E6-G6-C7 harmonics and warm decay
    private func generateStudioChimeWAV() -> Data? {
        let sampleRate: Double = 44100
        let duration: Double = 0.32
        let totalSamples = Int(sampleRate * duration)

        // Arpeggiated chord note offsets (C6 -> E6 -> G6 -> C7)
        let notes: [(freq: Double, start: Double, weight: Double)] = [
            (1046.50, 0.000, 0.30), // C6
            (1318.51, 0.025, 0.30), // E6
            (1567.98, 0.050, 0.25), // G6
            (2093.00, 0.075, 0.20)  // C7
        ]

        var samples = [Int16](repeating: 0, count: totalSamples)
        for i in 0..<totalSamples {
            let t = Double(i) / sampleRate
            var mixedSample: Double = 0

            for note in notes {
                if t >= note.start {
                    let noteT = t - note.start
                    let attack = min(1.0, noteT / 0.004)
                    let remainingDuration = duration - note.start
                    let decay = max(0.0, 1.0 - (noteT / remainingDuration))
                    let envelope = attack * pow(decay, 1.7)

                    // Pure fundamental + shimmer octave harmonic
                    let tone = sin(2.0 * .pi * note.freq * noteT) * 0.80 +
                               sin(2.0 * .pi * (note.freq * 2.0) * noteT) * 0.20
                    mixedSample += tone * envelope * note.weight
                }
            }

            let sample = mixedSample * 0.46
            samples[i] = Int16(max(-32767, min(32767, sample * 32767.0)))
        }

        return createWAVData(samples: samples, sampleRate: Int32(sampleRate))
    }

    private func createWAVData(samples: [Int16], sampleRate: Int32) -> Data {
        var data = Data()
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = sampleRate * Int32(numChannels * bitsPerSample / 8)
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = Int32(samples.count * MemoryLayout<Int16>.size)
        let chunkSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }

        return data
    }
}
