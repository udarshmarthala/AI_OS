import Foundation
import AVFoundation
import WhisperKit

@MainActor
final class VoiceInput: ObservableObject {
    enum State: Equatable { case idle, loading, recording, transcribing, denied }
    @Published var state: State = .idle

    private var whisper: WhisperKit?
    private let engine = AVAudioEngine()
    private var samples: [Float] = []

    func toggle(onText: @escaping (String) -> Void) {
        switch state {
        case .recording:
            stopAndTranscribe(onText: onText)
        case .idle:
            Task { await start() }
        default:
            break
        }
    }

    private func start() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            state = .denied
            return
        }
        if whisper == nil {
            state = .loading
            whisper = try? await WhisperKit(WhisperKitConfig(model: "base.en"))
            guard whisper != nil else { state = .idle; return }
        }
        samples = []
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)!

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            let ratio = 16000.0 / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var error: NSError?
            var consumed = false
            converter.convert(to: converted, error: &error) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = converted.floatChannelData else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel[0], count: Int(converted.frameLength)))
            Task { @MainActor [weak self] in self?.samples.append(contentsOf: chunk) }
        }

        do {
            try engine.start()
            state = .recording
        } catch {
            state = .idle
        }
    }

    private func stopAndTranscribe(onText: @escaping (String) -> Void) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = .transcribing
        let audio = samples
        Task {
            let results = try? await whisper?.transcribe(audioArray: audio)
            let text = results?.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            state = .idle
            if !text.isEmpty { onText(text) }
        }
    }
}
