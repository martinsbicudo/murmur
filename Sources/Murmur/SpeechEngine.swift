import AVFoundation
import CoreMedia
import Speech

enum SpeechEngineError: LocalizedError {
    case unsupportedLanguage(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let id):
            "Apple speech recognition doesn't support \"\(id)\". Set LANGUAGE in Settings (.env), e.g. en-US or pt-BR."
        case .unavailable:
            "Apple speech recognition isn't available on this Mac."
        }
    }
}

enum SpeechEngine {
    static func locale(for language: String) async throws -> Locale {
        let requested = language == "auto" ? Locale.current : Locale(identifier: language)
        guard SpeechTranscriber.isAvailable else { throw SpeechEngineError.unavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw SpeechEngineError.unsupportedLanguage(requested.identifier)
        }
        return supported
    }

    static func makeTranscriber(locale: Locale, live: Bool) async throws -> SpeechTranscriber {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: live ? [.volatileResults, .fastResults] : [],
            attributeOptions: [.audioTimeRange]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Log.write("downloading speech model for \(locale.identifier)")
            try await request.downloadAndInstall()
        }
        return transcriber
    }

    static func transcribeFile(_ url: URL, language: String, speaker: Speaker? = nil) async throws -> [TranscriptSegment] {
        let locale = try await locale(for: language)
        let transcriber = try await makeTranscriber(locale: locale, live: false)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collector = Task {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard Transcript.hasWords(text) else { continue }
                segments.append(TranscriptSegment(
                    start: CMTimeGetSeconds(result.range.start), text: text, speaker: speaker,
                    end: CMTimeGetSeconds(result.range.end)
                ))
            }
            return segments
        }
        let file = try AVAudioFile(forReading: url)
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        return try await collector.value
    }
}
