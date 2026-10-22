import AVFoundation
import Foundation

final class LiveAudioRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var transcribers: [Speaker: LiveTranscriber] = [:]

    func attach(_ transcriber: LiveTranscriber) {
        lock.withLock { transcribers[transcriber.speaker] = transcriber }
    }

    func detachAll() -> [LiveTranscriber] {
        lock.withLock {
            defer { transcribers = [:] }
            return Array(transcribers.values)
        }
    }

    func route(_ speaker: Speaker, _ buffer: AVAudioPCMBuffer) {
        lock.withLock { transcribers[speaker] }?.append(buffer)
    }
}

@MainActor
final class LiveSession {
    let model = LiveTranscriptModel()
    let chat = LiveChatModel { request in try await MeetingChat(config: Config.load()).answer(request) }
    let router = LiveAudioRouter()
    var onToggleMute: () -> Void = {}
    private lazy var window = LiveTranscriptWindow(model: model, chat: chat) { [weak self] in self?.onToggleMute() }
    private var startTask: Task<Void, Never>?

    var isWindowVisible: Bool { window.isVisible }

    func showWindow() {
        window.show()
    }

    func start(language: String, speakers: [Speaker], showWindow: Bool) {
        model.reset()
        chat.reset()
        model.setStatus("Preparing on-device speech recognition…")
        if showWindow { window.show() }
        let model = model
        let router = router
        startTask = Task {
            do {
                let locale = try await SpeechEngine.locale(for: language)
                for speaker in speakers {
                    let transcriber = try await LiveTranscriber.start(speaker: speaker, locale: locale) { update in
                        Task { @MainActor in model.apply(update) }
                    }
                    router.attach(transcriber)
                }
                model.setStatus(nil)
                Log.write("live transcription started (\(locale.identifier))")
            } catch {
                model.setStatus("Live transcript unavailable: \(error.localizedDescription)")
                Log.write("live transcription failed to start: \(error)")
            }
        }
    }

    func stop() async {
        startTask?.cancel()
        await startTask?.value
        for transcriber in router.detachAll() {
            await transcriber.finish()
        }
    }
}
