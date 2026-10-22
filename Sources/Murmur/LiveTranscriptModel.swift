import Foundation
import Observation

struct LiveBlock: Identifiable, Equatable {
    let id: Int
    let speaker: Speaker
    var finalText: String
    var volatileText: String

    var isEmpty: Bool { finalText.isEmpty && volatileText.isEmpty }
}

/// Live text from the microphone that repeats what the system track said in the last few seconds
/// is the other participants echoing through the speakers, so it's hidden instead of shown as You.
@MainActor
@Observable
final class LiveTranscriptModel {
    static let echoWindow: TimeInterval = 8

    private(set) var blocks: [LiveBlock] = []
    private(set) var status: String?
    private(set) var canMute = false
    private(set) var isMuted = false
    private(set) var muteWarning: String?
    private var openBlock: [Speaker: Int] = [:]
    private var nextID = 0
    private var recentOthers: [(time: Date, text: String)] = []
    private var othersVolatile = ""
    private var youUpdatedAt: [Int: Date] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func reset() {
        blocks = []
        status = nil
        openBlock = [:]
        nextID = 0
        recentOthers = []
        othersVolatile = ""
        youUpdatedAt = [:]
        canMute = false
        isMuted = false
        muteWarning = nil
    }

    func setCanMute(_ value: Bool) {
        canMute = value
    }

    func setMuted(_ muted: Bool, warning: String? = nil) {
        isMuted = muted
        muteWarning = muted ? warning : nil
        guard muted, let index = openBlock[.you] else { return }
        blocks[index].volatileText = ""
        openBlock[.you] = nil
        if blocks[index].isEmpty { removeBlock(at: index) }
    }

    var transcriptText: String {
        blocks.map { block in
            let text = [block.finalText, block.volatileText].filter { !$0.isEmpty }.joined(separator: " ")
            return "\(block.speaker.rawValue): \(text)"
        }.joined(separator: "\n")
    }

    func setStatus(_ message: String?) {
        status = message
    }

    func apply(_ update: LiveUpdate) {
        if update.speaker == .you, isMuted { return }
        let time = now()
        if update.speaker == .others { rememberOthers(update, at: time) }
        let heard = Transcript.hasWords(update.text) ? update.text : ""
        let text = update.speaker == .you && isEcho(heard, at: time) ? "" : heard
        let index = openBlock[update.speaker] ?? appendTarget(for: update.speaker)
        if update.isFinal {
            if !text.isEmpty {
                let separator = blocks[index].finalText.isEmpty ? "" : " "
                blocks[index].finalText += separator + text
            }
            blocks[index].volatileText = ""
            openBlock[update.speaker] = nil
        } else {
            blocks[index].volatileText = text
            openBlock[update.speaker] = index
        }
        if update.speaker == .you { youUpdatedAt[blocks[index].id] = time }
        if blocks[index].isEmpty { removeBlock(at: index) }
        if update.speaker == .others { removeEchoedYouBlocks(at: time) }
    }

    private func appendTarget(for speaker: Speaker) -> Int {
        if let last = blocks.indices.last, blocks[last].speaker == speaker { return last }
        blocks.append(LiveBlock(id: nextID, speaker: speaker, finalText: "", volatileText: ""))
        nextID += 1
        return blocks.count - 1
    }

    private func rememberOthers(_ update: LiveUpdate, at time: Date) {
        recentOthers.removeAll { time.timeIntervalSince($0.time) > Self.echoWindow }
        if update.isFinal {
            if !update.text.isEmpty { recentOthers.append((time, update.text)) }
            othersVolatile = ""
        } else {
            othersVolatile = update.text
        }
    }

    private func isEcho(_ text: String, at time: Date) -> Bool {
        let heard = recentOthers.filter { time.timeIntervalSince($0.time) <= Self.echoWindow }.map(\.text) + [othersVolatile]
        return TranscriptMerger.isEcho(text, of: heard.joined(separator: " "))
    }

    private func removeEchoedYouBlocks(at time: Date) {
        for index in blocks.indices.reversed() where blocks[index].speaker == .you {
            guard let updated = youUpdatedAt[blocks[index].id], time.timeIntervalSince(updated) <= Self.echoWindow else { continue }
            let text = [blocks[index].finalText, blocks[index].volatileText].filter { !$0.isEmpty }.joined(separator: " ")
            if isEcho(text, at: time) { removeBlock(at: index) }
        }
    }

    private func removeBlock(at index: Int) {
        let removed = blocks.remove(at: index)
        youUpdatedAt[removed.id] = nil
        openBlock = openBlock.compactMapValues { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) }
    }
}
