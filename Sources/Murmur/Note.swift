import Foundation

struct Note {
    let date: Date
    let duration: TimeInterval
    let audioName: String
    var transcript: Transcript?
    var summary: Summary?
    var problem: String?

    func write(to url: URL) throws {
        try render().write(to: url, atomically: true, encoding: .utf8)
    }

    func render() -> String {
        let dateText = date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
        var meta = [dateText, Self.format(duration), "[audio](\(audioName))"]
        if let transcript { meta.append("transcribed with \(transcript.engine)") }
        if let summary { meta.append("summarized with \(summary.engine)") }

        var parts = [
            "# \(summary?.title ?? Summarizer.defaultTitle)",
            "*" + meta.joined(separator: " · ") + "*",
        ]
        if let problem { parts.append("> **Note:** \(problem.replacingOccurrences(of: "\n", with: "\n> "))") }
        if let summary {
            parts.append(summary.body)
        } else if problem == nil {
            parts.append(transcript == nil ? "_Transcribing…_" : "_Summarizing…_")
        }
        parts.append("---")
        parts.append("## Transcript")
        switch transcript {
        case .none: parts.append("_Pending._")
        case .some(let transcript) where transcript.segments.isEmpty: parts.append("_No speech detected._")
        case .some(let transcript): parts.append(transcript.markdown)
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    static func format(_ duration: TimeInterval) -> String {
        if duration < 60 { return "\(Int(duration.rounded())) s" }
        let minutes = Int((duration / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
