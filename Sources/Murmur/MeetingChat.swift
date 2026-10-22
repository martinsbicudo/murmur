import Foundation

struct ChatTurn: Equatable {
    let question: String
    let answer: String
}

struct ChatRequest: Equatable {
    let transcript: String
    let history: [ChatTurn]
    let question: String
}

/// Answers questions about the meeting being recorded, from the live transcript only.
struct MeetingChat {
    static let defaultClaudeCodeModel = "sonnet"

    static let systemPrompt = """
    You answer quick questions about a meeting that is still in progress, using only its live transcript so far.

    The transcript is machine-generated in real time and may contain recognition errors. Each block is labeled \
    "You" (the user asking you, from their microphone) or "Others" (everyone else in the meeting, from the \
    computer's audio). Only state what the transcript supports. If it doesn't cover the question, say so plainly. \
    Never invent names, numbers, dates or commitments.

    Answer in the language of the question. Be brief: one to four sentences, or a few short bullets. \
    Plain text with at most **bold** for emphasis; no headings.
    """

    let config: Config

    static func model(for engine: SummaryEngine, config: Config) -> String? {
        config.string(engine.chatModelKey) ?? (engine == .claudeCode ? defaultClaudeCodeModel : config.string(engine.modelKey))
    }

    static func userMessage(for request: ChatRequest) -> String {
        var parts = ["<transcript>\n\(request.transcript)\n</transcript>"]
        if !request.history.isEmpty {
            let turns = request.history.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
            parts.append("<earlier_questions>\n\(turns)\n</earlier_questions>")
        }
        parts.append("<question>\n\(request.question)\n</question>")
        return parts.joined(separator: "\n\n")
    }

    func answer(_ request: ChatRequest) async throws -> String {
        let reply = try await AgentCLI(config: config).run(
            systemPrompt: Self.systemPrompt,
            userMessage: Self.userMessage(for: request),
            activity: "answering a live question"
        ) { Self.model(for: $0, config: config) }
        return reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
