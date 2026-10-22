import Testing
@testable import Murmur

struct EngineSelectionTests {
    @Test func defaultsToClaudeCode() {
        #expect(Config(values: [:]).summaryEngine == .claudeCode)
        #expect(Config(values: ["SUMMARY_ENGINE": "nonsense"]).summaryEngine == .claudeCode)
    }

    @Test func codexCanBeSelected() {
        #expect(Config(values: ["SUMMARY_ENGINE": "Codex"]).summaryEngine == .codex)
    }

    @Test func preferredEngineRunsFirstAndTheOtherIsTheFallback() {
        #expect(AgentCLI.engines(preferred: .claudeCode) { _ in true } == [.claudeCode, .codex])
        #expect(AgentCLI.engines(preferred: .codex) { _ in true } == [.codex, .claudeCode])
    }

    @Test func onlyInstalledEnginesAreUsed() {
        #expect(AgentCLI.engines(preferred: .claudeCode) { $0 == .codex } == [.codex])
        #expect(AgentCLI.engines(preferred: .claudeCode) { _ in false }.isEmpty)
    }
}
