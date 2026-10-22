import Foundation
import Testing
@testable import Murmur

struct ConfigTests {
    private func envFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-test-\(UUID().uuidString).env")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func readsKeysIgnoringCommentsBlankLinesAndExport() throws {
        let url = try envFile("""
        # comment
        SUMMARY_ENGINE=codex

        export LANGUAGE = pt-BR
        not a pair
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(Config.parse(url) == ["SUMMARY_ENGINE": "codex", "LANGUAGE": "pt-BR"])
    }

    @Test func stripsMatchingQuotesButKeepsEqualsInsideValues() throws {
        let url = try envFile("""
        A="quoted value"
        B='single'
        C="unbalanced'
        D=abc=def
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let values = Config.parse(url)
        #expect(values["A"] == "quoted value")
        #expect(values["B"] == "single")
        #expect(values["C"] == "\"unbalanced'")
        #expect(values["D"] == "abc=def")
    }

    @Test func missingFileYieldsNoValues() {
        #expect(Config.parse(URL(fileURLWithPath: "/nonexistent/murmur.env")).isEmpty)
    }

    @Test func emptyValuesCountAsUnset() {
        let config = Config(values: ["CODEX_MODEL": "  ", "LANGUAGE": "pt"])
        #expect(config.string("CODEX_MODEL") == nil)
        #expect(config.string("CODEX_MODEL", default: "x") == "x")
        #expect(config.language == "pt")
    }

    @Test func defaultsApplyWhenNothingIsSet() {
        let config = Config(values: [:])
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(config.notesDirectory.path == "\(home)/MeetingNotes")
        #expect(config.language == "auto")
        #expect(config.summaryEngine == .claudeCode)
        #expect(config.liveTranscript)
        #expect(config.hotKey == "ctrl+option+cmd+r")
        #expect(config.muteHotKey == "ctrl+option+cmd+m")
    }

    @Test func muteShortcutCanBeChangedOrTurnedOff() {
        #expect(Config(values: ["MUTE_HOTKEY": "cmd+shift+0"]).muteHotKey == "cmd+shift+0")
        #expect(Config(values: ["MUTE_HOTKEY": "off"]).muteHotKey == "off")
    }

    @Test func notesDirectoryExpandsTildeAndLiveTranscriptCanBeTurnedOff() {
        let config = Config(values: ["NOTES_DIR": "~/Notes/Meetings", "LIVE_TRANSCRIPT": "OFF"])
        #expect(config.notesDirectory.path == FileManager.default.homeDirectoryForCurrentUser.path + "/Notes/Meetings")
        #expect(!config.liveTranscript)
    }

    @Test func missingToolOverrideFallsBackToSearchPathsAndChildEnvironmentIsComplete() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let ls = Shell.find("ls", override: "~/definitely-missing-binary")
        #expect(ls?.path == "/bin/ls")
        #expect(Shell.environment["PATH"]?.hasPrefix("/opt/homebrew/bin:") == true)
        #expect(Shell.environment["PATH"]?.contains("\(home)/.local/bin") == true)
        #expect(Shell.environment["USER"]?.isEmpty == false)
    }
}
