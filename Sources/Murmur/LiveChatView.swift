import SwiftUI

struct LiveChatView: View {
    let chat: LiveChatModel
    let transcript: () -> String

    private static let bottomID = "chat-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !chat.messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(chat.messages) { ChatMessageView(message: $0) }
                            Color.clear.frame(height: 1).id(Self.bottomID)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .onChange(of: chat.messages) {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Ask about this meeting…", text: Binding(get: { chat.draft }, set: { chat.draft = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(chat.canSend ? Brand.gradient : AnyShapeStyle(.tertiary))
                .disabled(!chat.canSend)
                .help("Ask about what was said since the recording started")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func send() {
        let transcript = transcript()
        Task { await chat.send(transcript: transcript) }
    }
}

private struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.question)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Brand.gradient)
            if let answer = message.answer {
                Text(Self.formatted(answer))
            } else if let failure = message.failure {
                Text(failure).foregroundStyle(.orange)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static func formatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
