import Foundation

/// Google's Gemini CLI (`gemini -p`), in plan approval mode with no extensions, no MCP
/// servers, no hooks, no built-in tools and no GEMINI.md context files.
///
/// Each run gets its own `GEMINI_CLI_HOME`: a fresh folder whose `.gemini` holds only a
/// settings file (the person's chosen sign-in method, no tools, no context files) and
/// symbolic links to the sign-in files, deleted afterwards. That keeps the person's hooks,
/// MCP servers, memory and chat history out of the run. The system prompt replaces the
/// built-in one through `GEMINI_SYSTEM_MD`. (A system settings file can't be used: Gemini
/// ignores one whose folder isn't owned by root.)
///
/// Written from the documentation (geminicli.com/docs/cli/headless) and the installed
/// 0.63.0 bundle; not yet run signed in.
public struct GeminiProvider: AgentProvider {
  public let id = "gemini"
  public let name = "Gemini CLI"
  public let isLocal = false
  static let executable = "gemini"
  static let signInHint = "Run `gemini` in Terminal and sign in."
  /// Sign-in files linked into the run's home, when they exist.
  static let signInFiles = ["oauth_creds.json", "google_accounts.json"]

  public init() {}

  private static var realHome: URL {
    URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini", isDirectory: true)
  }

  public func status() async -> ProviderStatus {
    guard let path = Shell.which(Self.executable) else {
      return ProviderStatus(id: id, name: name, state: .notInstalled, verified: false)
    }
    let version = await ProviderCache.shared.version(of: path)
    let signedIn = ProviderRun.exists("~/.gemini/oauth_creds.json")
      || ProviderRun.environmentHas(["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GENAI_USE_VERTEXAI", "GOOGLE_GENAI_USE_GCA"])
    return ProviderStatus(
      id: id, name: name,
      state: signedIn ? .ready : .needsSignIn(hint: Self.signInHint),
      path: path, version: version, isLocal: isLocal,
      models: ["auto", "pro", "flash", "flash-lite"], verified: false
    )
  }

  /// The run's settings: no tools, no context files, no usage statistics, and the sign-in
  /// method from the person's own settings (a setting, not a credential).
  static func settings() -> String {
    var settings: [String: Any] = [
      "tools": ["core": [String]()],
      "context": ["fileName": "glade-no-context.md", "includeDirectoryTree": false],
      "privacy": ["usageStatisticsEnabled": false],
    ]
    let own = (try? Data(contentsOf: realHome.appendingPathComponent("settings.json")))
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    if let selected = ((own?["security"] as? [String: Any])?["auth"] as? [String: Any])?["selectedType"] as? String {
      settings["security"] = ["auth": ["selectedType": selected]]
    }
    return LooseJSON.string(settings) ?? "{}"
  }

  public func complete(_ request: AgentRequest) async throws -> AgentReply {
    let result = try await ProviderRun.withTemporaryFolder(id) { folder in
      let manager = FileManager.default
      let work = folder.appendingPathComponent("work", isDirectory: true)
      let dotGemini = folder.appendingPathComponent("home/.gemini", isDirectory: true)
      try manager.createDirectory(at: work, withIntermediateDirectories: true)
      try manager.createDirectory(at: dotGemini, withIntermediateDirectories: true)
      for file in Self.signInFiles {
        let real = Self.realHome.appendingPathComponent(file)
        if manager.fileExists(atPath: real.path) {
          try manager.createSymbolicLink(at: dotGemini.appendingPathComponent(file), withDestinationURL: real)
        }
      }
      try Data(Self.settings().utf8).write(to: dotGemini.appendingPathComponent("settings.json"))
      let systemFile = folder.appendingPathComponent("system.md")
      try Data(request.system.utf8).write(to: systemFile)

      var arguments = [
        "-p", "", "-o", "json", "--approval-mode", "plan", "--skip-trust",
        "-e", "none", "--allowed-mcp-server-names", "glade-none",
      ]
      if let model = request.model, !model.isEmpty { arguments += ["-m", model] }
      let environment = [
        "GEMINI_CLI_HOME": folder.appendingPathComponent("home").path,
        "GEMINI_SYSTEM_MD": systemFile.path,
      ]
      return try await ProviderRun.launch(id: id, provider: name, executable: Self.executable, arguments: arguments, input: request.prompt, environment: environment, directory: work, timeout: request.timeout)
    }
    return try parse(result, request: request)
  }

  private func parse(_ result: ShellResult, request: AgentRequest) throws -> AgentReply {
    let json = JSONExtractor.firstObject(in: result.stdout).flatMap(LooseJSON.object)
      ?? JSONExtractor.firstObject(in: result.stderr).flatMap(LooseJSON.object)
    let response = json?["response"] as? String

    guard result.status == 0, let response, !response.isEmpty else {
      ProviderRun.logFailure(provider: id, model: request.model, status: result.status, duration: result.duration, reason: "gemini error")
      let message = LooseJSON.errorMessage(json?["error"]) ?? (result.stderr.isEmpty ? result.stdout : result.stderr)
      switch result.status {
      case 41: throw AgentError.notSignedIn(provider: name, hint: Self.signInHint)
      case 55: throw AgentError.unavailable(provider: name, reason: "Gemini CLI refused to run outside a trusted folder.")
      default: throw ProviderRun.classify(provider: name, message: message, signInHint: Self.signInHint)
      }
    }

    var input: Int?, output: Int?, model = request.model
    if let models = (json?["stats"] as? [String: Any])?["models"] as? [String: Any] {
      model = models.keys.sorted().first ?? model
      for case let entry as [String: Any] in models.values {
        let tokens = entry["tokens"] as? [String: Any] ?? [:]
        if let value = LooseJSON.int(tokens["prompt"] ?? tokens["input"]) { input = (input ?? 0) + value }
        if let value = LooseJSON.int(tokens["candidates"]) { output = (output ?? 0) + value }
      }
    }
    let text = request.jsonSchema != nil ? try JSONExtractor.objectReply(response, provider: name) : response
    let reply = AgentReply(text: text, provider: id, model: model, inputTokens: input, outputTokens: output, duration: result.duration)
    ProviderRun.logSuccess(reply, status: result.status)
    return reply
  }
}
