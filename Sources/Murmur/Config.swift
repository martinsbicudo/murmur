import Foundation

struct Config {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/murmur", isDirectory: true)
    static let envFile = directory.appendingPathComponent(".env")

    private static let knownKeys = [
        "SUMMARY_ENGINE", "CLAUDE_CODE_", "CODEX_", "NOTES_DIR", "LANGUAGE", "FFMPEG_PATH", "HOTKEY", "MUTE_HOTKEY", "LIVE_TRANSCRIPT",
    ]

    let values: [String: String]

    static func load() -> Config {
        var values = parse(envFile)
        for (key, value) in ProcessInfo.processInfo.environment
        where knownKeys.contains(where: { key.hasPrefix($0) }) {
            values[key] = value
        }
        return Config(values: values)
    }

    static func parse(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line.removeFirst("export ".count) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    func string(_ key: String) -> String? {
        guard let value = values[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }

    func string(_ key: String, default fallback: String) -> String {
        string(key) ?? fallback
    }

    func path(_ key: String, default fallback: String) -> URL {
        URL(fileURLWithPath: NSString(string: string(key) ?? fallback).expandingTildeInPath)
    }

    var notesDirectory: URL { path("NOTES_DIR", default: "~/MeetingNotes") }
    var language: String { string("LANGUAGE", default: "auto") }
    var hotKey: String { string("HOTKEY", default: HotKeySpec.defaultValue) }
    var muteHotKey: String { string("MUTE_HOTKEY", default: HotKeySpec.defaultMuteValue) }
    var summaryEngine: SummaryEngine { SummaryEngine(rawValue: string("SUMMARY_ENGINE", default: "").lowercased()) ?? .claudeCode }
    var liveTranscript: Bool { string("LIVE_TRANSCRIPT", default: "on").lowercased() != "off" }
}
