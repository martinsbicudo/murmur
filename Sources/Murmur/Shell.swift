import Foundation

struct ShellError: LocalizedError {
    let command: String
    let status: Int32
    let stderr: String
    let stdout: String

    var errorDescription: String? {
        let output = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stdout : stderr
        let tail = output.split(separator: "\n").suffix(6).joined(separator: "\n")
        return "\(command) exited with \(status)\n\(tail)"
    }
}

enum Shell {
    static let searchPaths = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
    ]

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["USER"] = env["USER"] ?? NSUserName()
        env["LOGNAME"] = env["LOGNAME"] ?? NSUserName()
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        env["PATH"] = (searchPaths + [env["PATH"]].compactMap { $0 }).joined(separator: ":")
        return env
    }

    static func find(_ name: String, override: String? = nil) -> URL? {
        if let override {
            let expanded = NSString(string: override).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) { return URL(fileURLWithPath: expanded) }
        }
        return searchPaths
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    @discardableResult
    static func run(_ executable: URL, _ arguments: [String], input: String? = nil, in directory: URL? = nil) async throws -> String {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let outURL = workDir.appendingPathComponent("stdout")
        let errURL = workDir.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outHandle
        process.standardError = errHandle
        process.standardInput = FileHandle.nullDevice
        if let directory { process.currentDirectoryURL = directory }
        if let input {
            let inURL = workDir.appendingPathComponent("stdin")
            try input.write(to: inURL, atomically: true, encoding: .utf8)
            process.standardInput = try FileHandle(forReadingFrom: inURL)
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        try? outHandle.close()
        try? errHandle.close()

        let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        guard status == 0 else {
            let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
            throw ShellError(command: executable.lastPathComponent, status: status, stderr: stderr, stdout: stdout)
        }
        return stdout
    }
}

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Murmur.log")
    private static let queue = DispatchQueue(label: "murmur.log")

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        queue.async {
            FileHandle.standardError.write(Data(line.utf8))
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
