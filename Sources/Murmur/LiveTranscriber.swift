import AVFoundation
import Speech

struct LiveUpdate: Sendable {
    let speaker: Speaker
    let text: String
    let isFinal: Bool
}

/// Streams one audio source into Apple's on-device recognizer. `append` is called on the
/// capture queue, so it only converts and enqueues; recognition runs on the analyzer's own actor.
final class LiveTranscriber: @unchecked Sendable {
    let speaker: Speaker
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let resultsTask: Task<Void, Never>
    private var converter: AVAudioConverter?

    private init(
        speaker: Speaker, analyzer: SpeechAnalyzer, format: AVAudioFormat,
        input: AsyncStream<AnalyzerInput>.Continuation, resultsTask: Task<Void, Never>
    ) {
        self.speaker = speaker
        self.analyzer = analyzer
        self.format = format
        self.input = input
        self.resultsTask = resultsTask
    }

    static func start(
        speaker: Speaker, locale: Locale, onUpdate: @escaping @Sendable (LiveUpdate) -> Void
    ) async throws -> LiveTranscriber {
        let transcriber = try await SpeechEngine.makeTranscriber(locale: locale, live: true)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechEngineError.unavailable
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    onUpdate(LiveUpdate(speaker: speaker, text: text, isFinal: result.isFinal))
                }
            } catch {
                Log.write("live transcription (\(speaker.rawValue)) stopped: \(error)")
            }
        }
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)
        return LiveTranscriber(speaker: speaker, analyzer: analyzer, format: format, input: continuation, resultsTask: resultsTask)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async {
        input.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            Log.write("live transcription (\(speaker.rawValue)) finish failed: \(error)")
        }
        await resultsTask.value
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else {
            if let error { Log.write("live audio conversion failed: \(error)") }
            return nil
        }
        return output
    }
}
