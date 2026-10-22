import AppKit
import AVFoundation
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State {
        case idle
        case starting
        case recording(since: Date, stamp: String)
        case stopping
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recorder = AudioRecorder()
    private let notifier = Notifier()
    private let live = LiveSession()
    private let actions = AppActions()
    private let microphone = MicrophoneMuter(control: CoreAudioMicrophone())
    private var state = State.idle
    private var activeJobs: [String: String] = [:]
    private var lastNote: URL?
    private var timer: Timer?
    private lazy var recordingIcon = NSImage(named: "menubar-idle").map(RecordingIcon.init(mask:))
    private var hotKeys: [GlobalHotKey] = []
    private var hotKeySpec: HotKeySpec?
    private var muteHotKeySpec: HotKeySpec?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        notifier.activate()
        microphone.restore()
        live.onToggleMute = { [weak self] in self?.toggleMute() }
        recorder.onStreamError = { [weak self] error in
            Task { @MainActor in self?.streamFailed(error) }
        }
        registerHotKeys()
        refresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let busy: Bool
        switch state {
        case .idle: busy = !activeJobs.isEmpty
        default: busy = true
        }
        guard busy else { return .terminateNow }
        return Alerts.confirmQuitWhileBusy() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        microphone.restore()
    }

    private func registerHotKeys() {
        let config = Config.load()
        hotKeySpec = registerHotKey(config.hotKey, setting: "HOTKEY", id: 1, example: HotKeySpec.defaultValue) { [weak self] in
            self?.toggleRecording()
        }
        if let muteSpec = HotKeySpec.parse(config.muteHotKey), muteSpec == hotKeySpec {
            notify(title: "Invalid MUTE_HOTKEY", body: "MUTE_HOTKEY is the same shortcut as HOTKEY. Pick a different one.")
            return
        }
        muteHotKeySpec = registerHotKey(config.muteHotKey, setting: "MUTE_HOTKEY", id: 2, example: HotKeySpec.defaultMuteValue) { [weak self] in
            self?.toggleMute()
        }
    }

    private func registerHotKey(
        _ value: String, setting: String, id: UInt32, example: String, action: @escaping @MainActor () -> Void
    ) -> HotKeySpec? {
        guard value.lowercased() != "off" else { return nil }
        guard let spec = HotKeySpec.parse(value) else {
            notify(title: "Invalid \(setting)", body: "\"\(value)\" isn't a valid shortcut. Use something like \(example).")
            return nil
        }
        do {
            hotKeys.append(try GlobalHotKey(spec, id: id, setting: setting) {
                Task { @MainActor in action() }
            })
            Log.write("global shortcut \(spec.display) registered for \(setting)")
            return spec
        } catch {
            Log.write("global shortcut \(setting) failed: \(error.localizedDescription)")
            notify(title: "Shortcut unavailable", body: error.localizedDescription)
            return nil
        }
    }

    // MARK: Recording

    @objc private func toggleRecording() {
        switch state {
        case .idle: Task { await startRecording() }
        case .recording(let since, let stamp): Task { await stopRecording(startedAt: since, stamp: stamp) }
        default: break
        }
    }

    private func startRecording() async {
        state = .starting
        refresh()
        let config = Config.load()
        let micAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        if !micAllowed {
            notify(title: "Microphone access is off", body: "Recording system audio only. Enable Murmur in System Settings › Privacy & Security › Microphone.")
        }
        let now = Date()
        let stamp = NotePipeline.stamp(for: now)
        let router = live.router
        do {
            try await recorder.start(
                in: NotePipeline.workDirectory(for: stamp, config: config),
                includeMicrophone: micAllowed,
                onBuffer: { router.route($0, $1) }
            )
            state = .recording(since: now, stamp: stamp)
            live.start(
                language: config.language,
                speakers: micAllowed ? [.you, .others] : [.others],
                showWindow: config.liveTranscript
            )
            live.model.setCanMute(micAllowed)
            NSSound(named: "Tink")?.play()
            Log.write("recording started \(stamp)")
            startTimer()
        } catch {
            Log.write("could not start recording: \(error)")
            state = .idle
            Alerts.showPermissionHelp(error)
        }
        refresh()
    }

    private func stopRecording(startedAt: Date, stamp: String) async {
        state = .stopping
        setMuted(false)
        NSSound(named: "Pop")?.play()
        stopTimer()
        refresh()
        let tracks: RecordedTracks
        do {
            tracks = try await recorder.stop()
        } catch {
            state = .idle
            refresh()
            notify(title: "Recording failed", body: error.localizedDescription)
            return
        }
        state = .idle
        await live.stop()
        Log.write("recording stopped \(stamp), tracks: \(tracks.tracks.map(\.url.lastPathComponent))")
        runJob(id: stamp) { pipeline in
            try await pipeline.finish(tracks: tracks, startedAt: startedAt)
        }
    }

    @objc private func toggleMute() {
        guard case .recording = state, live.model.canMute else { return }
        setMuted(!live.model.isMuted)
        refresh()
    }

    private func setMuted(_ muted: Bool) {
        guard muted != live.model.isMuted else { return }
        recorder.setMicrophoneMuted(muted)
        guard muted else {
            microphone.restore()
            live.model.setMuted(false)
            Log.write("microphone unmuted")
            return
        }
        do {
            try microphone.mute()
            live.model.setMuted(true)
            Log.write("microphone muted")
        } catch {
            live.model.setMuted(true, warning: error.localizedDescription)
            Log.write("microphone muted in Murmur only: \(error)")
        }
    }

    private func streamFailed(_ error: Error) {
        guard case .recording(let since, let stamp) = state else { return }
        notify(title: "Recording interrupted", body: error.localizedDescription)
        Task { await stopRecording(startedAt: since, stamp: stamp) }
    }

    private func runJob(id: String, _ work: @escaping (NotePipeline) async throws -> URL) {
        activeJobs[id] = "Processing…"
        refresh()
        var pipeline = NotePipeline(config: Config.load())
        pipeline.onProgress = { [weak self] message in
            Task { @MainActor in
                self?.activeJobs[id] = message
                self?.refresh()
            }
        }
        Task {
            do {
                let note = try await work(pipeline)
                lastNote = note
                Log.write("note written \(note.path)")
                notify(title: "Meeting notes ready", body: note.lastPathComponent, open: note)
            } catch {
                Log.write("processing failed: \(error)")
                notify(title: "Processing failed", body: error.localizedDescription)
            }
            activeJobs[id] = nil
            refresh()
        }
    }

    // MARK: Menu actions

    @objc private func openLastNote() {
        guard let note = lastNote ?? AppActions.latestNote() else { return }
        NSWorkspace.shared.open(note)
    }

    @objc private func showLiveTranscript() {
        live.showWindow()
    }

    @objc private func reprocessFile() {
        guard let path = AppActions.chooseAudioOrRecording() else { return }
        runJob(id: path.path) { pipeline in
            try await pipeline.process(path: path)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            notify(title: "Couldn't change Launch at Login", body: error.localizedDescription)
        }
        refresh()
    }

    // MARK: UI

    private func refresh() {
        updateButton()
        statusItem.menu = buildMenu()
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let recording: Bool
        if case .recording = state { recording = true } else { recording = false }
        if recording, let recordingIcon {
            recordingIcon.start(in: button)
        } else {
            recordingIcon?.stop()
            let image = NSImage(named: "menubar-idle")
            image?.isTemplate = true
            image?.size = RecordingIcon.size
            button.image = image
        }
        button.imagePosition = .imageLeading
        if case .recording(let since, _) = state {
            let elapsed = Self.timerTitle(Transcript.timestamp(Date().timeIntervalSince(since)))
            button.attributedTitle = live.model.isMuted ? Self.mutedTitle(elapsed) : elapsed
        } else if !activeJobs.isEmpty {
            button.attributedTitle = Self.timerTitle("…")
        } else {
            button.title = ""
        }
        button.toolTip = live.model.isMuted ? "Murmur · microphone muted" : "Murmur"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let toggle: NSMenuItem
        switch state {
        case .idle:
            toggle = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
        case .starting:
            toggle = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        case .recording:
            toggle = NSMenuItem(title: "Stop Recording", action: #selector(toggleRecording), keyEquivalent: "")
        case .stopping:
            toggle = NSMenuItem(title: "Stopping…", action: nil, keyEquivalent: "")
        }
        if let hotKeySpec, toggle.action != nil {
            toggle.keyEquivalent = hotKeySpec.key
            toggle.keyEquivalentModifierMask = hotKeySpec.modifierFlags
        }
        menu.addItem(toggle)
        for status in activeJobs.values.sorted() {
            menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        }
        if case .recording = state, live.model.canMute {
            let title = live.model.isMuted ? "Unmute Microphone" : "Mute Microphone"
            let mute = NSMenuItem(title: title, action: #selector(toggleMute), keyEquivalent: muteHotKeySpec?.key ?? "")
            if let muteHotKeySpec { mute.keyEquivalentModifierMask = muteHotKeySpec.modifierFlags }
            menu.addItem(mute)
        }
        menu.addItem(NSMenuItem(title: "Show Live Transcript", action: #selector(showLiveTranscript), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Last Note", action: #selector(openLastNote), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Open Notes Folder", action: #selector(AppActions.openNotesFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Process Audio File…", action: #selector(reprocessFile), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings (.env)…", action: #selector(AppActions.openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Show Log", action: #selector(AppActions.openLog), keyEquivalent: ""))
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Murmur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let actionSelectors: Set<Selector> = [#selector(AppActions.openNotesFolder), #selector(AppActions.openSettings), #selector(AppActions.openLog)]
        for item in menu.items {
            guard let action = item.action, action != #selector(NSApplication.terminate(_:)) else { continue }
            item.target = actionSelectors.contains(action) ? actions : self
        }
        return menu
    }

    private static func mutedTitle(_ elapsed: NSAttributedString) -> NSAttributedString {
        guard let symbol = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "Microphone muted") else { return elapsed }
        let attachment = NSTextAttachment()
        attachment.image = symbol.withSymbolConfiguration(.init(pointSize: NSFont.systemFontSize - 1, weight: .semibold))
        let title = NSMutableAttributedString(string: " ")
        title.append(NSAttributedString(attachment: attachment))
        title.append(elapsed)
        return title
    }

    private static func timerTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: " \(text)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
        )
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateButton() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func notify(title: String, body: String, open url: URL? = nil) {
        notifier.post(title: title, body: body, opening: url)
    }
}
