import AppKit
import SwiftUI

@MainActor
final class LiveTranscriptWindow {
    private let panel: NSPanel

    init(model: LiveTranscriptModel, chat: LiveChatModel, onToggleMute: @escaping () -> Void) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = "Murmur · Live"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 280, height: 240)
        panel.contentView = NSHostingView(rootView: LiveTranscriptView(model: model, chat: chat, onToggleMute: onToggleMute))
        panel.setFrameAutosaveName("MurmurLiveTranscript")
        if !panel.setFrameUsingName("MurmurLiveTranscript"), let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 440, y: frame.minY + 40))
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct LiveTranscriptView: View {
    let model: LiveTranscriptModel
    let chat: LiveChatModel
    let onToggleMute: () -> Void

    private static let bottomID = "bottom"

    var body: some View {
        VStack(spacing: 0) {
            if model.canMute {
                MuteBar(model: model, onToggle: onToggleMute)
                Divider()
            }
            transcript
            Divider()
            LiveChatView(chat: chat) { model.transcriptText }
        }
        .background(.regularMaterial)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let status = model.status {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                    }
                    if model.blocks.isEmpty, model.status == nil {
                        Text("Listening…").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(model.blocks) { block in
                        BlockView(block: block, style: block.speaker == .you ? Brand.gradient : AnyShapeStyle(.secondary))
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.blocks) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }
}

private struct MuteBar: View {
    let model: LiveTranscriptModel
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onToggle) {
                Label(model.isMuted ? "Unmute" : "Mute", systemImage: model.isMuted ? "mic.slash.fill" : "mic.fill")
            }
            .tint(model.isMuted ? .red : nil)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(model.isMuted ? "Turn your microphone back on" : "Mute your microphone for every app and stop recording what you say")
            Text(Self.caption(muted: model.isMuted, warning: model.muteWarning))
                .font(.caption)
                .foregroundStyle(model.muteWarning == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private static func caption(muted: Bool, warning: String?) -> String {
        guard muted else { return "Your mic is on" }
        guard let warning else { return "Muted for every app. Others are still recorded." }
        return "Murmur stopped recording you, but other apps can still hear you. \(warning)"
    }
}

private struct BlockView: View {
    let block: LiveBlock
    let style: AnyShapeStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(block.speaker.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(style)
            (Text(block.finalText) + Text(block.finalText.isEmpty || block.volatileText.isEmpty ? "" : " ")
                + Text(block.volatileText).foregroundColor(.secondary))
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
