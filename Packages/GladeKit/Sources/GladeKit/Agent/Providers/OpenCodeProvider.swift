import Foundation

/// OpenCode (`opencode run`), run with a private server and a one-off agent whose tools
/// are all switched off. Project config and Claude Code compatibility files are ignored.
public struct OpenCodeProvider: AgentProvider {
  public let id = "opencode"
  public let name = "OpenCode"
  public let isLocal = false
  static let executable = "opencode"
  static let signInHint = "Run `opencode auth login` in Terminal."

  public init() {}

  public func status() async -> ProviderStatus {
    guard let path = Shell.which(Self.executable) else {
      return ProviderStatus(id: id, name: name, state: .notInstalled)
    }
    let version = await ProviderCache.shared.version(of: path)
    let models = await ProviderCache.shared.models(id, executable: path, arguments: ["models"]) { output in
      output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains("/") }
    }
    // OpenCode's own free models need no sign-in, so a missing auth file isn't a blocker
    // as long as a model is chosen; `complete` reports when the default model refuses.
    let signedIn = ProviderRun.exists("~/.local/share/opencode/auth.json") || !models.isEmpty
    return ProviderStatus(
      id: id, name: name,
      state: signedIn ? .ready : .needsSignIn(hint: Self.signInHint),
      path: path, version: version, isLocal: isLocal, models: models
    )
  }

  public func complete(_ request: AgentRequest) async throws -> AgentReply {
    let config: [String: Any] = [
      // `"*": false` leaves the skill tool on, so it's named as well.
      "agent": ["inert": [
        "mode": "primary", "prompt": request.system,
        "tools": ["*": false, "skill": false],
        "permission": ["skill": "deny"],
      ]],
      "mcp": [String: Any](),
      "share": "disabled",
      "autoupdate": false,
    ]
    guard let configText = LooseJSON.string(config) else {
      throw AgentError.failed(provider: name, detail: "The system prompt couldn’t be encoded.")
    }
    var arguments = ["run", "--standalone", "--format", "json", "--agent", "inert"]
    if let model = request.model, !model.isEmpty { arguments += ["-m", model] }
    let environment = [
      "OPENCODE_CONFIG_CONTENT": configText,
      "OPENCODE_DISABLE_PROJECT_CONFIG": "1",
      "OPENCODE_DISABLE_CLAUDE_CODE": "1",
    ]
    let result = try await ProviderRun.withTemporaryFolder(id) { folder in
      try await ProviderRun.launch(id: id, provider: name, executable: Self.executable, arguments: arguments, input: request.prompt, environment: environment, directory: folder, timeout: request.timeout)
    }
    return try parse(result, request: request)
  }

  private func parse(_ result: ShellResult, request: AgentRequest) throws -> AgentReply {
    var text = ""
    var input = 0, output = 0, cost = 0.0
    var sawUsage = false
    var errors: [String] = []
    for event in LooseJSON.lines(result.stdout) {
      let part = event["part"] as? [String: Any] ?? [:]
      switch event["type"] as? String {
      case "text":
        text += part["text"] as? String ?? ""
      case "step_finish":
        if let tokens = part["tokens"] as? [String: Any] {
          sawUsage = true
          let cache = tokens["cache"] as? [String: Any] ?? [:]
          input += [tokens["input"], cache["read"], cache["write"]].compactMap(LooseJSON.int).reduce(0, +)
          output += [tokens["output"], tokens["reasoning"]].compactMap(LooseJSON.int).reduce(0, +)
        }
        cost += LooseJSON.double(part["cost"]) ?? 0
      case "error":
        errors.append(LooseJSON.errorMessage(event["error"]) ?? LooseJSON.string(event) ?? "error")
      default:
        break
      }
    }

    if !errors.isEmpty || result.status != 0 || text.isEmpty {
      let message = errors.last ?? (result.stderr.isEmpty ? "OpenCode finished without a reply." : result.stderr)
      ProviderRun.logFailure(provider: id, model: request.model, status: result.status, duration: result.duration, reason: "opencode error")
      if message.lowercased().contains("free models may train") {
        throw AgentError.unavailable(provider: name, reason: "Its default free model may train on what it’s sent. Choose a model (for example `opencode/claude-haiku-5-5`).")
      }
      if message.lowercased().contains("model not found") || message.lowercased().contains("providermodelnotfound") {
        throw AgentError.failed(provider: name, detail: ProviderRun.excerpt("Unknown model. \(message)"))
      }
      throw ProviderRun.classify(provider: name, message: message, signInHint: Self.signInHint)
    }
    let replyText = request.jsonSchema != nil ? try JSONExtractor.objectReply(text, provider: name) : text
    let reply = AgentReply(
      text: replyText, provider: id, model: request.model,
      inputTokens: sawUsage ? input : nil,
      outputTokens: sawUsage ? output : nil,
      costUSD: sawUsage ? cost : nil,
      duration: result.duration
    )
    ProviderRun.logSuccess(reply, status: result.status)
    return reply
  }
}
