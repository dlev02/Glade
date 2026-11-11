import Foundation

/// Cursor's command-line agent (`cursor-agent -p`). It has no switch to remove its tools,
/// so each run happens in an empty folder whose `.cursor/cli.json` denies every shell,
/// read, write, web and MCP permission (deny rules win over the person's allow list), and
/// `--force` is never passed. Cursor has no system prompt option, so the system prompt is
/// put ahead of the prompt under a clear heading.
///
/// Written from the documentation (cursor.com/docs/cli); not yet run signed in.
/// `cursor-agent status` is never called: it starts a sign-in flow and waits.
public struct CursorProvider: AgentProvider {
  public let id = "cursor"
  public let name = "Cursor CLI"
  public let isLocal = false
  static let executable = "cursor-agent"
  static let signInHint = "Run `cursor-agent login` in Terminal."

  static let permissions = #"{"permissions":{"allow":[],"deny":["Shell(*)","Read(**)","Write(**)","WebFetch(*)","Mcp(*:*)"]}}"#

  public init() {}

  public func status() async -> ProviderStatus {
    guard let path = Shell.which(Self.executable) else {
      return ProviderStatus(id: id, name: name, state: .notInstalled, verified: false)
    }
    let version = await ProviderCache.shared.version(of: path)
    var signedIn = ProviderRun.environmentHas(["CURSOR_API_KEY"])
    if !signedIn { signedIn = await ProviderRun.keychainHas(service: "cursor-access-token", account: "cursor-user") }
    if !signedIn { signedIn = await ProviderRun.keychainHas(service: "cursor-api-key", account: "cursor-user") }
    return ProviderStatus(
      id: id, name: name,
      state: signedIn ? .ready : .needsSignIn(hint: Self.signInHint),
      path: path, version: version, isLocal: isLocal, verified: false
    )
  }

  public func complete(_ request: AgentRequest) async throws -> AgentReply {
    let result = try await ProviderRun.withTemporaryFolder(id) { folder in
      let settings = folder.appendingPathComponent(".cursor", isDirectory: true)
      try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
      try Data(Self.permissions.utf8).write(to: settings.appendingPathComponent("cli.json"))
      var arguments = ["-p", "--output-format", "json"]
      if let model = request.model, !model.isEmpty { arguments += ["--model", model] }
      return try await ProviderRun.launch(
        id: id, provider: name, executable: Self.executable, arguments: arguments,
        input: ProviderRun.combined(system: request.system, prompt: request.prompt),
        directory: folder, timeout: request.timeout
      )
    }
    let json = JSONExtractor.firstObject(in: result.stdout).flatMap(JSONValue.object)
    let text = json?["result"] as? String ?? ""
    guard result.status == 0, json?["is_error"] as? Bool != true, !text.isEmpty else {
      ProviderRun.logFailure(provider: id, model: request.model, status: result.status, duration: result.duration, reason: "cursor error")
      let message = result.stderr.isEmpty ? (text.isEmpty ? result.stdout : text) : result.stderr
      let lower = message.lowercased()
      if lower.contains("authentication required") || lower.contains("sign in") || lower.contains("login") {
        throw AgentError.notSignedIn(provider: name, hint: Self.signInHint)
      }
      throw ProviderRun.classify(provider: name, message: message, signInHint: Self.signInHint)
    }
    let replyText = request.jsonSchema != nil ? try JSONExtractor.objectReply(text, provider: name) : text
    let reply = AgentReply(text: replyText, provider: id, model: request.model, duration: result.duration)
    ProviderRun.logSuccess(reply, status: result.status)
    return reply
  }
}
