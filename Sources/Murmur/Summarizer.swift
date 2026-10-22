import Foundation

struct Summary: Equatable {
    let title: String
    let body: String
    let engine: String
}

struct Summarizer {
    let config: Config

    static let systemPrompt = """
    You turn raw meeting transcripts into short, accurate meeting notes.

    The transcript is machine-generated and may contain recognition errors. Each line is labeled \
    "You" (the user, from their microphone) or "Others" (everyone else in the meeting, from the computer's audio). \
    Unlabeled lines come from a single mixed recording. Only state what the transcript supports; \
    never invent names, dates or commitments.

    Write in the same language the meeting was held in. Respond with Markdown in exactly this shape \
    and nothing else:

    # <short descriptive meeting title, max 8 words>

    ## Summary
    - <exactly 5 bullets covering the most important points, one sentence each>

    ## Decisions
    - <each decision that was made; write "- None recorded." if there were none>

    ## Action items
    - [ ] **<Owner>**: <task> (due <date>, only if one was mentioned)

    For action items, use "You" when the user commits to something, the person's name when the transcript \
    makes it clear, and "Unassigned" otherwise. Write "- None recorded." if there were none.
    """

    static let defaultTitle = "Meeting notes"

    func summarize(_ transcript: Transcript) async throws -> Summary {
        let reply = try await AgentCLI(config: config).run(
            systemPrompt: Self.systemPrompt,
            userMessage: "<transcript>\n\(transcript.markdown)\n</transcript>",
            activity: "summarizing"
        ) { config.string($0.modelKey) }
        return Self.parse(reply.text, engine: reply.label)
    }

    static func parse(_ text: String, engine: String) -> Summary {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        var title = defaultTitle
        if let first = lines.first, first.hasPrefix("# ") {
            title = String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.removeFirst()
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Summary(title: title, body: body, engine: engine)
    }
}
