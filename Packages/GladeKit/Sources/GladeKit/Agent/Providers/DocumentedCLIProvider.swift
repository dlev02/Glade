import Foundation

/// How to drive a command-line agent Glade knows only from its documentation: what to
/// run, how the prompt goes in and how the answer comes out. One table entry per tool.
public struct CLISpec: Sendable {
  public enum SystemPrompt: Sendable {
    /// Passed with this flag.
    case flag(String)
    /// Put ahead of the prompt on standard input.
    case prepended
  }

  public enum Output: Sendable {
    /// Standard output is the reply.
    case plainText
    /// A JSON array (or JSON Lines) whose `{"type":"result"}` entry holds `result`,
    /// `is_error` and `usage`.
    case resultEvent
  }

  public var id: String
  public var name: String
  public var executable: String
  /// Everything except the model and system prompt flags. The prompt always goes on stdin.
  public var arguments: [String]
  public var modelFlag: String
  public var systemPrompt: SystemPrompt
  public var output: Output
  /// Files whose existence means signed in. Only checked for existence.
  public var signInFiles: [String]
  public var signInEnvironment: [String]
  public var signInHint: String
  public var environment: [String: String] = [:]
  public var models: [String] = []
  /// Where the integration's details come from.
  public var documentation: String
}

extension CLISpec {
  /// Tools whose documentation gives a clean, non-interactive, text-out mode with their
  /// tools held back. Grok Build, Kimi, Amp, Goose and Aider are left out: their headless
  /// modes either approve tool calls automatically or can't switch tools off.
  public static let documented: [CLISpec] = [
    CLISpec(
      id: "qwen", name: "Qwen Code", executable: "qwen",
      // A Gemini CLI fork: stdin is read ahead of the empty -p prompt. Safe mode skips
      // context files, extensions, MCP servers, skills, hooks and memory.
      arguments: ["-p", "", "-o", "json", "--approval-mode", "plan", "--safe-mode"],
      modelFlag: "-m", systemPrompt: .flag("--system-prompt"), output: .resultEvent,
      signInFiles: ["~/.qwen/oauth_creds.json"],
      signInEnvironment: ["DASHSCOPE_API_KEY", "QWEN_API_KEY"],
      signInHint: "Run `qwen` in Terminal and sign in.",
      environment: ["QWEN_CODE_SAFE_MODE": "true"],
      documentation: "https://github.com/QwenLM/qwen-code/blob/main/docs/users/features/headless.md"
    ),
    CLISpec(
      id: "copilot", name: "GitHub Copilot CLI", executable: "copilot",
      // `-s` prints only the final answer; piped stdin is the prompt. No tools, no
      // custom instructions, no built-in MCP servers, never asks the person anything.
      arguments: ["-s", "--no-custom-instructions", "--disable-builtin-mcps", "--no-ask-user", "--available-tools="],
      modelFlag: "--model", systemPrompt: .prepended, output: .plainText,
      signInFiles: ["~/.copilot"],
      signInEnvironment: ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"],
      signInHint: "Run `copilot` in Terminal and sign in with /login.",
      documentation: "https://docs.github.com/en/copilot/reference/cli-command-reference"
    ),
  ]
}

/// A provider driven entirely by a `CLISpec`. Marked unverified: none of these tools have
/// been run here.
public struct DocumentedCLIProvider: AgentProvider {
  public let spec: CLISpec
  public var id: String { spec.id }
  public var name: String { spec.name }
  public var isLocal: Bool { false }

  public init(spec: CLISpec) {
    self.spec = spec
  }

  public func status() async -> ProviderStatus {
    guard let path = Shell.which(spec.executable) else {
      return ProviderStatus(id: id, name: name, state: .notInstalled, verified: false)
    }
    let version = await ProviderCache.shared.version(of: path)
    let signedIn = spec.signInFiles.contains(where: ProviderRun.exists) || ProviderRun.environmentHas(spec.signInEnvironment)
    return ProviderStatus(
      id: id, name: name,
      state: signedIn ? .ready : .needsSignIn(hint: spec.signInHint),
      path: path, version: version, isLocal: isLocal, models: spec.models, verified: false
    )
  }

  public func complete(_ request: AgentRequest) async throws -> AgentReply {
    var arguments = spec.arguments
    var input = request.prompt
    switch spec.systemPrompt {
    case .flag(let flag): arguments += [flag, request.system]
    case .prepended: input = ProviderRun.combined(system: request.system, prompt: request.prompt)
    }
    if let model = request.model, !model.isEmpty { arguments += [spec.modelFlag, model] }
    let result = try await ProviderRun.withTemporaryFolder(id) { folder in
      try await ProviderRun.launch(id: id, provider: name, executable: spec.executable, arguments: arguments, input: input, environment: spec.environment, directory: folder, timeout: request.timeout)
    }

    var text = ""
    var usage: [String: Any] = [:]
    var failed = result.status != 0
    switch spec.output {
    case .plainText:
      text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    case .resultEvent:
      let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      let events = ((try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [[String: Any]]) ?? LooseJSON.lines(trimmed)
      if let final = events.last(where: { $0["type"] as? String == "result" }) {
        text = final["result"] as? String ?? ""
        usage = final["usage"] as? [String: Any] ?? [:]
        if final["is_error"] as? Bool == true { failed = true }
      }
    }
    if failed || text.isEmpty {
      ProviderRun.logFailure(provider: id, model: request.model, status: result.status, duration: result.duration, reason: "\(id) error")
      let message = result.stderr.isEmpty ? (text.isEmpty ? result.stdout : text) : result.stderr
      throw ProviderRun.classify(provider: name, message: message, signInHint: spec.signInHint)
    }
    let replyText = request.jsonSchema != nil ? try JSONExtractor.objectReply(text, provider: name) : text
    let reply = AgentReply(
      text: replyText, provider: id, model: request.model,
      inputTokens: LooseJSON.int(usage["input_tokens"]),
      outputTokens: LooseJSON.int(usage["output_tokens"]),
      duration: result.duration
    )
    ProviderRun.logSuccess(reply, status: result.status)
    return reply
  }
}
