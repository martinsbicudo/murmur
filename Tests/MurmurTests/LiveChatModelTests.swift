import Foundation
import Testing
@testable import Murmur

@MainActor
private final class HeldAnswers {
    var requests: [ChatRequest] = []
    private var waiting: [CheckedContinuation<String, Error>] = []

    func answer(_ request: ChatRequest) async throws -> String {
        requests.append(request)
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }

    func waitForRequest() async {
        while waiting.isEmpty { await Task.yield() }
    }

    func reply(_ text: String) {
        waiting.removeFirst().resume(returning: text)
    }
}

private struct Offline: LocalizedError {
    var errorDescription: String? { "Claude Code failed: Not logged in" }
}

@MainActor
struct LiveChatModelTests {
    private let transcript = "Others: Let's ship on Friday.\nYou: I'll write the release notes."

    @Test func answersAQuestionAboutTheTranscriptSoFar() async {
        var received: ChatRequest?
        let chat = LiveChatModel { request in
            received = request
            return "Friday."
        }
        chat.draft = "  When do we ship?  "
        await chat.send(transcript: transcript)
        #expect(received == ChatRequest(transcript: transcript, history: [], question: "When do we ship?"))
        #expect(chat.messages == [ChatMessage(id: 0, question: "When do we ship?", answer: "Friday.")])
        #expect(chat.draft.isEmpty)
    }

    @Test func followUpQuestionsCarryTheEarlierAnswers() async {
        var received: [ChatRequest] = []
        let chat = LiveChatModel { request in
            received.append(request)
            return "Answer \(received.count)"
        }
        chat.draft = "When do we ship?"
        await chat.send(transcript: transcript)
        chat.draft = "Who writes the notes?"
        await chat.send(transcript: transcript)
        #expect(received.last?.history == [ChatTurn(question: "When do we ship?", answer: "Answer 1")])
    }

    @Test func failedQuestionsAreShownAndNotReusedAsHistory() async {
        var received: [ChatRequest] = []
        let chat = LiveChatModel { request in
            received.append(request)
            if received.count == 1 { throw Offline() }
            return "ok"
        }
        chat.draft = "First?"
        await chat.send(transcript: transcript)
        #expect(chat.messages.first?.failure == "Claude Code failed: Not logged in")
        chat.draft = "Again?"
        await chat.send(transcript: transcript)
        #expect(received.last?.history == [])
        #expect(chat.messages.last?.answer == "ok")
    }

    @Test func nothingIsSentBeforeAnyoneHasTalked() async {
        var called = false
        let chat = LiveChatModel { _ in
            called = true
            return "?"
        }
        chat.draft = "What was decided?"
        await chat.send(transcript: "  ")
        #expect(!called)
        #expect(chat.messages.first?.answer == LiveChatModel.nothingRecordedYet)
    }

    @Test func blankQuestionsAreNotSent() async {
        let chat = LiveChatModel { _ in "?" }
        chat.draft = "   "
        #expect(!chat.canSend)
        await chat.send(transcript: transcript)
        #expect(chat.messages.isEmpty)
    }

    @Test func oneQuestionAtATime() async {
        let held = HeldAnswers()
        let chat = LiveChatModel { try await held.answer($0) }
        chat.draft = "First?"
        let first = Task { await chat.send(transcript: transcript) }
        await held.waitForRequest()
        #expect(chat.isAsking)
        chat.draft = "Second?"
        #expect(!chat.canSend)
        await chat.send(transcript: transcript)
        #expect(held.requests.count == 1)
        held.reply("Done.")
        await first.value
        #expect(!chat.isAsking)
        #expect(chat.canSend)
    }

    @Test func aNewRecordingDropsALateAnswerFromThePreviousOne() async {
        let held = HeldAnswers()
        let chat = LiveChatModel { try await held.answer($0) }
        chat.draft = "Old question?"
        let pending = Task { await chat.send(transcript: transcript) }
        await held.waitForRequest()
        chat.reset()
        held.reply("Old answer.")
        await pending.value
        #expect(chat.messages.isEmpty)
        #expect(!chat.isAsking)
    }
}

struct MeetingChatTests {
    @Test func sendsTheTranscriptAndTheQuestion() {
        let message = MeetingChat.userMessage(for: ChatRequest(transcript: "Others: Hi.", history: [], question: "Who spoke?"))
        #expect(message == "<transcript>\nOthers: Hi.\n</transcript>\n\n<question>\nWho spoke?\n</question>")
    }

    @Test func includesEarlierQuestionsForFollowUps() {
        let request = ChatRequest(
            transcript: "Others: Hi.", history: [ChatTurn(question: "Who spoke?", answer: "Others.")], question: "What did they say?"
        )
        #expect(MeetingChat.userMessage(for: request).contains("<earlier_questions>\nQ: Who spoke?\nA: Others.\n</earlier_questions>"))
    }

    @Test func claudeCodeChatsWithSonnetUnlessConfigured() {
        #expect(MeetingChat.model(for: .claudeCode, config: Config(values: ["CLAUDE_CODE_MODEL": "opus"])) == "sonnet")
        #expect(MeetingChat.model(for: .claudeCode, config: Config(values: ["CLAUDE_CODE_CHAT_MODEL": "haiku"])) == "haiku")
    }

    @Test func codexChatsWithItsChatModelOrItsSummaryModel() {
        #expect(MeetingChat.model(for: .codex, config: Config(values: [:])) == nil)
        #expect(MeetingChat.model(for: .codex, config: Config(values: ["CODEX_MODEL": "gpt-5.5"])) == "gpt-5.5")
        #expect(MeetingChat.model(for: .codex, config: Config(values: ["CODEX_MODEL": "a", "CODEX_CHAT_MODEL": "b"])) == "b")
    }

    @Test func promptKeepsAnswersToTheTranscript() {
        #expect(MeetingChat.systemPrompt.contains("\"You\" (the user"))
        #expect(MeetingChat.systemPrompt.contains("If it doesn't cover the question, say so"))
    }

    @Test func replyLabelNamesTheEngineAndModel() {
        #expect(AgentReply(text: "", engine: .claudeCode, model: "sonnet").label == "Claude Code sonnet")
        #expect(AgentReply(text: "", engine: .codex, model: nil).label == "Codex")
    }
}
