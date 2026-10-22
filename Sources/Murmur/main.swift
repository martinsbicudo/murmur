import AppKit

let arguments = CommandLine.arguments

if let flag = arguments.firstIndex(of: "--process"), flag + 1 < arguments.count {
    let audio = URL(fileURLWithPath: arguments[flag + 1])
    var pipeline = NotePipeline(config: Config.load())
    pipeline.onProgress = { print($0) }
    Task {
        do {
            let note = try await pipeline.process(path: audio)
            print(note.path)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
