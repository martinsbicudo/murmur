import AVFoundation
import ScreenCaptureKit

struct RecordedTrack {
    let url: URL
    let speaker: Speaker
}

struct RecordedTracks {
    static let fileNames: [Speaker: String] = [.you: "mic.caf", .others: "system.caf"]

    let directory: URL
    let tracks: [RecordedTrack]

    static func load(from directory: URL) -> RecordedTracks? {
        let tracks = Speaker.allCases.compactMap { speaker -> RecordedTrack? in
            guard let name = fileNames[speaker] else { return nil }
            let url = directory.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? RecordedTrack(url: url, speaker: speaker) : nil
        }
        return tracks.isEmpty ? nil : RecordedTracks(directory: directory, tracks: tracks)
    }
}

enum RecorderError: LocalizedError {
    case noDisplay
    case notRecording

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No display available to capture system audio from."
        case .notRecording: "Not recording."
        }
    }
}

final class AudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "murmur.audio")
    private var stream: SCStream?
    private var directory: URL?
    private var writers: [Speaker: TrackWriter] = [:]
    private var clockStart: CMTime?
    private var onBuffer: ((Speaker, AVAudioPCMBuffer) -> Void)?
    private var microphoneMuted = false

    var onStreamError: ((Error) -> Void)?

    func start(
        in directory: URL,
        includeMicrophone: Bool,
        onBuffer: ((Speaker, AVAudioPCMBuffer) -> Void)? = nil
    ) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.captureMicrophone = includeMicrophone
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        queue.sync {
            self.directory = directory
            self.onBuffer = onBuffer
            let speakers: [Speaker] = includeMicrophone ? [.you, .others] : [.others]
            writers = Dictionary(uniqueKeysWithValues: speakers.compactMap { speaker in
                RecordedTracks.fileNames[speaker].map { (speaker, TrackWriter(url: directory.appendingPathComponent($0))) }
            })
            clockStart = nil
            microphoneMuted = false
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        if includeMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws -> RecordedTracks {
        guard let stream, let directory else { throw RecorderError.notRecording }
        self.stream = nil
        do {
            try await stream.stopCapture()
        } catch {
            Log.write("stopCapture failed: \(error)")
        }
        return queue.sync {
            writers.values.forEach { $0.close() }
            let tracks = writers.filter { $0.value.hasAudio }.map { RecordedTrack(url: $0.value.url, speaker: $0.key) }
            writers = [:]
            onBuffer = nil
            return RecordedTracks(directory: directory, tracks: tracks.sorted { $0.speaker.rawValue < $1.speaker.rawValue })
        }
    }

    /// While muted the microphone is simply not written; `TrackWriter` fills the gap with silence
    /// when it comes back, so both tracks stay aligned.
    func setMicrophoneMuted(_ muted: Bool) {
        queue.async { self.microphoneMuted = muted }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        let speaker: Speaker
        switch type {
        case .audio: speaker = .others
        case .microphone: speaker = .you
        default: return
        }
        if speaker == .you, microphoneMuted { return }
        guard let buffer = TrackWriter.pcmBuffer(from: sampleBuffer) else { return }
        let start = clockStart ?? sampleBuffer.presentationTimeStamp
        clockStart = start
        writers[speaker]?.append(buffer, presentationTime: sampleBuffer.presentationTimeStamp, clockStart: start)
        onBuffer?(speaker, buffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.write("stream stopped with error: \(error)")
        onStreamError?(error)
    }
}
