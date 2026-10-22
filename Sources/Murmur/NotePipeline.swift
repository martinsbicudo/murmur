import AVFoundation
import Foundation

/// The note is rewritten after each step, so a failure later on never loses the audio or transcript.
struct NotePipeline {
    let config: Config
    var onProgress: (String) -> Void = { _ in }

    private static let stampFormat = "yyyy-MM-dd-HHmm"
    private static let workPrefix = ".recording-"

    static func stamp(for date: Date) -> String {
        stampFormatter().string(from: date)
    }

    static func date(fromStamp name: String) -> Date? {
        stampFormatter().date(from: String(name.prefix(stampFormat.count)))
    }

    static func workDirectory(for stamp: String, config: Config) -> URL {
        config.notesDirectory.appendingPathComponent(workPrefix + stamp, isDirectory: true)
    }

    static func recordingDate(ofWorkDirectory directory: URL) -> Date? {
        let name = directory.lastPathComponent
        guard name.hasPrefix(workPrefix) else { return nil }
        return date(fromStamp: String(name.dropFirst(workPrefix.count)))
    }

    static func uniqueBase(in directory: URL, stamp: String) -> URL {
        var candidate = directory.appendingPathComponent(stamp)
        var counter = 2
        while ["m4a", "md"].contains(where: { FileManager.default.fileExists(atPath: candidate.appendingPathExtension($0).path) }) {
            candidate = directory.appendingPathComponent("\(stamp)-\(counter)")
            counter += 1
        }
        return candidate
    }

    static func mixArguments(inputs: [URL], output: URL) -> [String] {
        var args = ["-hide_banner", "-loglevel", "error", "-y"]
        inputs.forEach { args += ["-i", $0.path] }
        if inputs.count > 1 {
            let normalized = inputs.indices.map { "[\($0):a]aformat=sample_rates=48000:channel_layouts=stereo[a\($0)]" }
            let labels = inputs.indices.map { "[a\($0)]" }.joined()
            let graph = normalized.joined(separator: ";")
                + ";\(labels)amix=inputs=\(inputs.count):duration=longest:normalize=0,alimiter=limit=0.95[out]"
            args += ["-filter_complex", graph, "-map", "[out]"]
        }
        return args + ["-c:a", "aac", "-b:a", "128k", output.path]
    }

    func finish(tracks: RecordedTracks, startedAt: Date) async throws -> URL {
        guard !tracks.tracks.isEmpty else { throw PipelineError.silent }
        let base = Self.uniqueBase(in: config.notesDirectory, stamp: Self.stamp(for: startedAt))
        let audio = base.appendingPathExtension("m4a")
        onProgress("Saving audio…")
        try await mix(tracks.tracks.map(\.url), into: audio)
        let note = try await process(audio: audio, startedAt: startedAt) {
            var bySpeaker: [Speaker: [TranscriptSegment]] = [:]
            for track in tracks.tracks {
                bySpeaker[track.speaker] = try await SpeechEngine.transcribeFile(track.url, language: config.language)
            }
            return TranscriptMerger.merge(you: bySpeaker[.you] ?? [], others: bySpeaker[.others] ?? [])
        }
        do {
            try FileManager.default.removeItem(at: tracks.directory)
        } catch {
            Log.write("couldn't remove raw tracks at \(tracks.directory.path): \(error)")
        }
        return note
    }

    func process(path: URL) async throws -> URL {
        guard let tracks = RecordedTracks.load(from: path) else { return try await process(audio: path) }
        return try await finish(tracks: tracks, startedAt: Self.recordingDate(ofWorkDirectory: path) ?? Date())
    }

    func process(audio: URL, startedAt: Date? = nil) async throws -> URL {
        try await process(audio: audio, startedAt: startedAt) {
            try await SpeechEngine.transcribeFile(audio, language: config.language)
        }
    }

    private func process(
        audio: URL, startedAt: Date?, transcribe: () async throws -> [TranscriptSegment]
    ) async throws -> URL {
        let noteURL = audio.deletingPathExtension().appendingPathExtension("md")
        var note = Note(
            date: startedAt ?? Self.date(fromStamp: audio.deletingPathExtension().lastPathComponent) ?? Date(),
            duration: await Self.duration(of: audio),
            audioName: audio.lastPathComponent
        )
        try note.write(to: noteURL)

        onProgress("Transcribing…")
        let transcript: Transcript
        do {
            transcript = Transcript(segments: try await transcribe(), engine: "Apple on-device speech")
        } catch {
            note.problem = error.localizedDescription
            try note.write(to: noteURL)
            throw error
        }
        note.transcript = transcript
        try note.write(to: noteURL)

        onProgress("Summarizing…")
        do {
            note.summary = try await Summarizer(config: config).summarize(transcript)
        } catch {
            note.problem = "Summary failed: \(error.localizedDescription)"
        }
        try note.write(to: noteURL)
        return noteURL
    }

    private func mix(_ files: [URL], into output: URL) async throws {
        guard let ffmpeg = Shell.find("ffmpeg", override: config.string("FFMPEG_PATH")) else {
            throw PipelineError.missingFFmpeg
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await Shell.run(ffmpeg, Self.mixArguments(inputs: files, output: output))
    }

    private static func duration(of audio: URL) async -> TimeInterval {
        guard let time = try? await AVURLAsset(url: audio).load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? seconds : 0
    }

    private static func stampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = stampFormat
        return formatter
    }
}

enum PipelineError: LocalizedError {
    case silent
    case missingFFmpeg

    var errorDescription: String? {
        switch self {
        case .silent: "No audio was captured. Check Microphone and Screen & System Audio Recording permissions."
        case .missingFFmpeg: "ffmpeg not found. Install it with `make deps`."
        }
    }
}
