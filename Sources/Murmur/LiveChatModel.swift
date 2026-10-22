import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    let id: Int
    let question: String
    var answer: String?
    var failure: String?

    var isPending: Bool { answer == nil && failure == nil }
}

/// The question-and-answer thread under the live transcript. It belongs to one recording: `reset()`
/// clears it, and an answer that arrives after a reset is dropped.
@MainActor
@Observable
final class LiveChatModel {
    static let nothingRecordedYet = "Nothing has been transcribed yet. Ask again once people have talked."

    private(set) var messages: [ChatMessage] = []
    var draft = ""
    private var nextID = 0
    private var session = 0
    private let answer: (ChatRequest) async throws -> String

    init(answer: @escaping (ChatRequest) async throws -> String) {
        self.answer = answer
    }

    var isAsking: Bool { messages.contains(where: \.isPending) }

    var canSend: Bool { !isAsking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send(transcript: String) async {
        guard canSend else { return }
        let question = draft
        draft = ""
        await ask(question, transcript: transcript)
    }

    func reset() {
        messages = []
        draft = ""
        nextID = 0
        session += 1
    }

    private func ask(_ question: String, transcript: String) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }
        let id = nextID
        nextID += 1
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            messages.append(ChatMessage(id: id, question: question, answer: Self.nothingRecordedYet))
            return
        }
        let history = messages.compactMap { message in message.answer.map { ChatTurn(question: message.question, answer: $0) } }
        messages.append(ChatMessage(id: id, question: question))
        let asked = session
        let request = ChatRequest(transcript: transcript, history: history, question: question)
        do {
            let text = try await answer(request)
            guard asked == session else { return }
            update(id) { $0.answer = text }
        } catch {
            guard asked == session else { return }
            update(id) { $0.failure = error.localizedDescription }
        }
    }

    private func update(_ id: Int, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }
}
