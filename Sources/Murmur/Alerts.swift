import AppKit

@MainActor
enum Alerts {
    static func confirmQuitWhileBusy() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Murmur is still recording or processing"
        alert.informativeText = "Quitting now loses the note in progress. Raw audio stays in ~/MeetingNotes/.recording-* and can be reprocessed later."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit Anyway")
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func showPermissionHelp(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Murmur couldn't start recording"
        alert.informativeText = """
        \(error.localizedDescription)

        Murmur needs "Screen & System Audio Recording" permission to capture meeting audio. \
        Enable it in System Settings › Privacy & Security, then quit and reopen Murmur.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
