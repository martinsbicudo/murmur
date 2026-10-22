import Foundation
import Testing
@testable import Murmur

struct SummarizerTests {
    @Test func extractsTitleFromFirstHeading() {
        let summary = Summarizer.parse("\n# Launch sync\n\n## Summary\n- One\n", engine: "X")
        #expect(summary == Summary(title: "Launch sync", body: "## Summary\n- One", engine: "X"))
    }

    @Test func usesDefaultTitleWhenModelSkipsTheHeading() {
        let summary = Summarizer.parse("## Summary\n- One", engine: "X")
        #expect(summary.title == Summarizer.defaultTitle)
        #expect(summary.body == "## Summary\n- One")
    }

    @Test func readsTheResultFromClaudeCodeJSONOutput() throws {
        let output = ##"{"type":"result","subtype":"success","is_error":false,"num_turns":1,"result":"# Title\n## Summary"}"##
        #expect(try AgentCLI.claudeCodeText(output) == "# Title\n## Summary")
    }

    @Test func claudeCodeErrorsAreSurfacedNotSavedAsSummary() {
        let output = #"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}"#
        #expect(throws: AgentCLIError.failed(engine: "Claude Code", detail: "Not logged in · Please run /login")) {
            try AgentCLI.claudeCodeText(output)
        }
    }

    @Test func claudeCodeRunLimitsAreErrors() {
        #expect(throws: AgentCLIError.failed(engine: "Claude Code", detail: "error_max_turns")) {
            try AgentCLI.claudeCodeText(#"{"type":"result","subtype":"error_max_turns","is_error":false}"#)
        }
    }

    @Test func emptyClaudeCodeResultIsAnError() {
        #expect(throws: AgentCLIError.emptyResponse("Claude Code")) {
            try AgentCLI.claudeCodeText(#"{"type":"result","subtype":"success","is_error":false,"result":"  "}"#)
        }
    }

    @Test func claudeCodeRunsWithoutToolsSettingsOrMCP() {
        let args = AgentCLI.claudeCodeArguments(model: nil, systemPrompt: Summarizer.systemPrompt)
        #expect(args.starts(with: ["-p", "--output-format", "json"]))
        #expect(args.contains("--strict-mcp-config"))
        #expect(args.contains("--no-session-persistence"))
        #expect(args.firstIndex(of: "--tools").map { args[$0 + 1] } == "")
        #expect(args.firstIndex(of: "--setting-sources").map { args[$0 + 1] } == "project")
        #expect(!args.contains("--model"))
        #expect(AgentCLI.claudeCodeArguments(model: "sonnet", systemPrompt: "p").suffix(2) == ["--model", "sonnet"])
    }

    @Test func codexRunsReadOnlyEphemeralAndReadsPromptFromStdin() {
        let args = AgentCLI.codexArguments(
            model: "gpt-5.5", workDir: URL(fileURLWithPath: "/tmp/w"), output: URL(fileURLWithPath: "/tmp/w/s.md")
        )
        #expect(args.first == "exec")
        #expect(args.last == "-")
        #expect(args.firstIndex(of: "-s").map { args[$0 + 1] } == "read-only")
        #expect(args.firstIndex(of: "-o").map { args[$0 + 1] } == "/tmp/w/s.md")
        #expect(args.firstIndex(of: "-m").map { args[$0 + 1] } == "gpt-5.5")
        #expect(["--ephemeral", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check"].allSatisfy(args.contains))
        #expect(!AgentCLI.codexArguments(model: nil, workDir: URL(fileURLWithPath: "/w"), output: URL(fileURLWithPath: "/w/o")).contains("-m"))
    }

    @Test func promptExplainsTheSpeakerLabels() {
        #expect(Summarizer.systemPrompt.contains("\"You\" (the user"))
        #expect(Summarizer.systemPrompt.contains("\"Others\""))
    }
}
