import Foundation

/// Claude Code (`claude`), run in print mode with every tool, MCP server, slash command,
/// settings file and saved session switched off.
public struct ClaudeProvider: AgentProvider {
  public let id = "claude"
  public let name = "Claude Code"
  public let isLocal = false
  static let executable = "claude"
  static let signInHint = "Run `claude` in Terminal and sign in with /login."

  public init() {}

  public func status() async -> ProviderStatus {
    guard let path = Shell.which(Self.executable) else {
      return ProviderStatus(id: id, name: name, state: .notInstalled, supportsEffort: true)
    }
    let version = await ProviderCache.shared.version(of: path)
    var signedIn = ProviderRun.exists("~/.claude/.credentials.json")
      || ProviderRun.environmentHas(["ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"])
    if !signedIn { signedIn = await ProviderRun.keychainHas(service: "Claude Code-credentials") }
    return ProviderStatus(
      id: id, name: name,
      state: signedIn ? .ready : .needsSignIn(hint: Self.signInHint),
      path: path, version: version, isLocal: isLocal, supportsEffort: true,
      models: ["haiku", "sonnet", "opus", "fable"]
    )
  }

  public func complete(_ request: AgentRequest) async throws -> AgentReply {
    var arguments = [
      "-p", "--output-format", "json",
      "--tools", "",
      "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
      "--disable-slash-commands",
      "--no-session-persistence",
      "--setting-sources", "",
      "--system-prompt", request.system,
    ]
    if let model = request.model, !model.isEmpty { arguments += ["--model", model] }
    if request.effort != .automatic { arguments += ["--effort", request.effort.rawValue] }
    if let schema = request.jsonSchema { arguments += ["--json-schema", schema] }

    let result = try await ProviderRun.withTemporaryFolder(id) { folder in
      try await ProviderRun.launch(id: id, provider: name, executable: Self.executable, arguments: arguments, input: request.prompt, directory: folder, timeout: request.timeout)
    }
    return try parse(result, request: request)
  }

  private func parse(_ result: ShellResult, request: AgentRequest) throws -> AgentReply {
    guard let json = JSONValue.object(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
      ?? JSONValue.lines(result.stdout).last(where: { $0["type"] as? String == "result" })
    else {
      ProviderRun.logFailure(provider: id, model: request.model, status: result.status, duration: result.duration, reason: "no JSON")
      throw ProviderRun.classify(provider: name, message: result.stderr.isEmpty ? result.stdout : result.stderr, signInHint: Self.signInHint)
    }
    let usage = json["usage"] as? [String: Any] ?? [:]
    let model = (json["modelUsage"] as? [String: Any])?.keys.sorted().first ?? request.model
    let text = json["result"] as? String ?? ""

    if json["is_error"] as? Bool == true || result.status != 0 {
      let status = JSONValue.int(json["api_error_status"])
      ProviderRun.logFailure(provider: id, model: model, status: result.status, duration: result.duration, reason: "api status \(status.map(String.init) ?? "none")")
      let message = text.isEmpty ? (result.stderr.isEmpty ? "subtype \(json["subtype"] as? String ?? "unknown")" : result.stderr) : text
      switch status {
      case 429: throw AgentError.rateLimited(provider: name, detail: ProviderRun.excerpt(message))
      case 401, 403: throw AgentError.notSignedIn(provider: name, hint: Self.signInHint)
      default: throw ProviderRun.classify(provider: name, message: message, signInHint: Self.signInHint)
      }
    }

    var replyText = text
    if request.jsonSchema != nil {
      if let structured = json["structured_output"], let serialised = JSONValue.string(structured) {
        replyText = serialised
      } else {
        replyText = try JSONExtractor.objectReply(text, provider: name)
      }
    }
    let input = [usage["input_tokens"], usage["cache_creation_input_tokens"], usage["cache_read_input_tokens"]]
      .compactMap(JSONValue.int).reduce(0, +)
    let reply = AgentReply(
      text: replyText, provider: id, model: model,
      inputTokens: usage.isEmpty ? nil : input,
      outputTokens: JSONValue.int(usage["output_tokens"]),
      costUSD: JSONValue.double(json["total_cost_usd"]),
      duration: result.duration
    )
    ProviderRun.logSuccess(reply, status: result.status)
    return reply
  }
}
