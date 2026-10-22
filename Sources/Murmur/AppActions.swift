import AppKit

/// Menu actions that only touch files and settings, not the recording state.
@MainActor
final class AppActions: NSObject {
    static func latestNote() -> URL? {
        let dir = Config.load().notesDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.max { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func chooseAudioOrRecording() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = true
        panel.directoryURL = Config.load().notesDirectory
        panel.message = "Choose an audio file, or a leftover .recording folder, to transcribe and summarize"
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    @objc func openNotesFolder() {
        let dir = Config.load().notesDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Log.write("couldn't create \(dir.path): \(error)")
        }
        NSWorkspace.shared.open(dir)
    }

    @objc func openSettings() {
        let env = Config.envFile
        if !FileManager.default.fileExists(atPath: env.path) {
            do {
                try FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
                if let template = Bundle.main.url(forResource: "env", withExtension: "example") {
                    try FileManager.default.copyItem(at: template, to: env)
                } else {
                    FileManager.default.createFile(atPath: env.path, contents: nil)
                }
            } catch {
                Log.write("couldn't create \(env.path): \(error)")
            }
        }
        NSWorkspace.shared.open(
            [env],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc func openLog() {
        NSWorkspace.shared.open(Log.url)
    }
}
