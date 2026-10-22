import Foundation

enum Speaker: String, CaseIterable, Sendable {
    case you = "You"
    case others = "Others"
}

struct TranscriptSegment: Equatable, Sendable {
    let start: Double
    let text: String
    var speaker: Speaker?
    var end: Double?
}

struct Transcript {
    let segments: [TranscriptSegment]
    let engine: String

    private static let maxParagraphLength = 600

    var markdown: String {
        Self.paragraphs(segments).map { segment in
            let label = segment.speaker.map { " \($0.rawValue):" } ?? ""
            return "**[\(Self.timestamp(segment.start))]\(label)** \(segment.text)"
        }.joined(separator: "\n\n")
    }

    static func hasWords(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func paragraphs(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for segment in segments {
            if let last = result.last, last.speaker != nil, last.speaker == segment.speaker,
               last.text.count + segment.text.count < maxParagraphLength {
                result[result.count - 1] = TranscriptSegment(start: last.start, text: last.text + " " + segment.text, speaker: last.speaker, end: segment.end)
            } else {
                result.append(segment)
            }
        }
        return result
    }
}

/// On speakers (no headphones) the microphone also hears the other participants, so their speech
/// shows up on both tracks. The recognizer hears the echo badly, so the copy is rarely word for word:
/// a microphone segment is an echo when most of its words were said on the system track at that time.
enum TranscriptMerger {
    static let echoWindow = 3.0
    static let echoContainment = 0.5

    static func merge(you: [TranscriptSegment], others: [TranscriptSegment]) -> [TranscriptSegment] {
        let labeledOthers = others.map { TranscriptSegment(start: $0.start, text: $0.text, speaker: .others, end: $0.end) }
        let labeledYou = you
            .map { TranscriptSegment(start: $0.start, text: $0.text, speaker: .you, end: $0.end) }
            .filter { !isEcho($0, against: labeledOthers) }
        return (labeledOthers + labeledYou).sorted { ($0.start, $0.speaker == .you ? 1 : 0) < ($1.start, $1.speaker == .you ? 1 : 0) }
    }

    static func isEcho(_ candidate: TranscriptSegment, against others: [TranscriptSegment]) -> Bool {
        let from = candidate.start - echoWindow
        let to = (candidate.end ?? candidate.start) + echoWindow
        let reference = others
            .filter { $0.start <= to && ($0.end ?? $0.start) >= from }
            .map(\.text)
            .joined(separator: " ")
        return isEcho(candidate.text, of: reference)
    }

    static func isEcho(_ text: String, of reference: String) -> Bool {
        let mine = words(text)
        guard !mine.isEmpty else { return false }
        let heard = words(reference)
        return Double(mine.intersection(heard).count) / Double(mine.count) >= echoContainment
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}
