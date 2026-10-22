import Foundation

enum AgentCLIError: LocalizedError, Equatable {
    case notInstalled(String)
    case failed(engine: String, detail: String)
    case emptyResponse(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let tool): "\(tool) isn't installed or wasn't found in ~/.local/bin, /opt/homebrew/bin or /usr/local/bin."
        case .failed(let engine, let detail): "\(engine) failed: \(detail)"
        case .emptyResponse(let engine): "\(engine) returned an empty answer."
        }
    }
}

enum SummaryEngine: String, CaseIterable {
    case claudeCode = "claude-code"
    case codex

    var displayName: String { self == .claudeCode ? "Claude Code" : "Codex" }
    var binaryName: String { self == .claudeCode ? "claude" : "codex" }
    var binaryKey: String { self == .claudeCode ? "CLAUDE_CODE_BIN" : "CODEX_BIN" }
    var modelKey: String { self == .claudeCode ? "CLAUDE_CODE_MODEL" : "CODEX_MODEL" }
    var chatModelKey: String { self == .claudeCode ? "CLAUDE_CODE_CHAT_MODEL" : "CODEX_CHAT_MODEL" }
}

struct AgentReply: Equatable {
    let text: String
    let engine: SummaryEngine
    let model: String?

    var label: String { engine.displayName + (model.map { " \($0)" } ?? "") }
}

/// Runs one prompt through the Claude Code or Codex CLI login, headless and without tools, trying the
/// preferred engine first and the other one if it fails.
struct AgentCLI {
    let config: Config

    func run(
        systemPrompt: String, userMessage: String, activity: String, model: (SummaryEngine) -> String?
    ) async throws -> AgentReply {
        let engines = Self.engines(preferred: config.summaryEngine) { engine in binary(for: engine) != nil }
        guard !engines.isEmpty else { throw AgentCLIError.notInstalled("Claude Code (claude) or Codex (codex)") }
        var lastError: Error = AgentCLIError.notInstalled(config.summaryEngine.displayName)
        for engine in engines {
            do {
                Log.write("\(activity) with \(engine.displayName)")
                let chosenModel = model(engine)
                let text = try await run(engine, model: chosenModel, systemPrompt: systemPrompt, userMessage: userMessage)
                return AgentReply(text: text, engine: engine, model: chosenModel)
            } catch {
                Log.write("\(activity) with \(engine.displayName) failed: \(error.localizedDescription)")
                lastError = error
            }
        }
        throw lastError
    }

    static func engines(preferred: SummaryEngine, isInstalled: (SummaryEngine) -> Bool) -> [SummaryEngine] {
        ([preferred] + SummaryEngine.allCases.filter { $0 != preferred }).filter(isInstalled)
    }

    static func claudeCodeText(_ output: String) throws -> String {
        let result = try JSONDecoder.snakeCase.decode(ClaudeCodeResult.self, from: Data(output.utf8))
        guard result.isError != true, result.subtype == nil || result.subtype == "success" else {
            throw AgentCLIError.failed(engine: "Claude Code", detail: result.result ?? result.subtype ?? "unknown error")
        }
        return try nonEmpty(result.result ?? "", engine: "Claude Code")
    }

    static func claudeCodeArguments(model: String?, systemPrompt: String) -> [String] {
        var args = [
            "-p", "--output-format", "json",
            "--setting-sources", "project", "--strict-mcp-config", "--no-session-persistence",
            "--tools", "", "--system-prompt", systemPrompt,
        ]
        if let model { args += ["--model", model] }
        return args
    }

    static func codexArguments(model: String?, workDir: URL, output: URL) -> [String] {
        var args = [
            "exec", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--ignore-rules",
            "-s", "read-only", "-C", workDir.path, "-o", output.path,
        ]
        if let model { args += ["-m", model] }
        return args + ["-"]
    }

    static func codexPrompt(systemPrompt: String, userMessage: String) -> String {
        systemPrompt + "\n\nDo not run commands or read files; answer only from this transcript.\n\n" + userMessage
    }

    static func nonEmpty(_ text: String, engine: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentCLIError.emptyResponse(engine) }
        return text
    }

    private func binary(for engine: SummaryEngine) -> URL? {
        Shell.find(engine.binaryName, override: config.string(engine.binaryKey))
    }

    private func run(_ engine: SummaryEngine, model: String?, systemPrompt: String, userMessage: String) async throws -> String {
        guard let binary = binary(for: engine) else { throw AgentCLIError.notInstalled(engine.displayName) }
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("murmur-\(engine.rawValue)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        switch engine {
        case .claudeCode:
            let args = Self.claudeCodeArguments(model: model, systemPrompt: systemPrompt)
            do {
                let output = try await Shell.run(binary, args, input: userMessage, in: workDir)
                return try Self.claudeCodeText(output)
            } catch let error as ShellError where !error.stdout.isEmpty {
                _ = try Self.claudeCodeText(error.stdout)
                throw error
            }
        case .codex:
            let output = workDir.appendingPathComponent("answer.md")
            let prompt = Self.codexPrompt(systemPrompt: systemPrompt, userMessage: userMessage)
            try await Shell.run(binary, Self.codexArguments(model: model, workDir: workDir, output: output), input: prompt, in: workDir)
            return try Self.nonEmpty(try String(contentsOf: output, encoding: .utf8), engine: "Codex")
        }
    }
}

struct ClaudeCodeResult: Decodable {
    let subtype: String?
    let isError: Bool?
    let result: String?
}

extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
