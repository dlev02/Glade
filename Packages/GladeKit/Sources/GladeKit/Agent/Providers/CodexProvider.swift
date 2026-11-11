import Foundation

/// OpenAI Codex (`codex exec`), run ephemerally in a read-only sandbox with its shell,
/// apps, plugins, memories, hooks, MCP servers and project instructions switched off.
///
/// Codex reads global memory and instructions from its home folder even with
/// `--ignore-user-config`, so each run gets its own `CODEX_HOME`: a fresh folder holding
/// only a symbolic link to the person's `auth.json`, deleted afterwards.
public struct CodexProvider: AgentProvider {
  public let id = "codex"
  public let name = "Codex"
  public let isLocal = false
  static let executable = "codex"
  static let signInHint = "Run `codex login` in Terminal."

  /// Features that give the model tools or outside context. Unknown names are ignored by
  /// Codex, so the list can stay ahead of or behind the installed version. Checked with
  /// `codex debug prompt-input` on 0.167.1: with these off the shell (`exec_command`) is
  /// gone. `apply_patch` and the sub-agent tools can't be switched off; the read-only
  /// sandbox stops the first from writing, and sub-agents inherit this configuration.
  static let disabledFeatures = [
    "shell_tool", "unified_exec", "code_mode_host", "apps", "plugins", "memories", "hooks",
    "multi_agent", "sleep_tool", "image_generation", "browser_use", "computer_use",
    "in_app_browser", "view_image", "skill_search", "chronicle",
  ]

  public init() {}

  private static var realAuth: URL {
    URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")
  }

  public func status() async -> ProviderStatus {
    guard let path = Shell.which(Self.executable) else {
      return ProviderStatus(id: id, name: name, state: .notInstalled, supportsEffort: true)
    }
    let version = await ProviderCache.shared.version(of: path)
    let signedIn = ProviderRun.exists(Self.realAuth.path) || ProviderRun.environmentHas(["CODEX_API_KEY"])
    let models = await ProviderCache.shared.models(id, executable: path, arguments: ["debug", "models"]) { output in
      guard let list = LooseJSON.object(output)?["models"] as? [[String: Any]] else { return [] }
      return list.filter { $0["visibility"] as? String != "hide" }.compactMap { $0["slug"] as? String }
    }
    return ProviderStatus(
      id: id, name: name,
      state: signedIn ? .ready : .needsSignIn(hint: Self.signInHint),
      path: path, version: version, isLocal: isLocal, supportsEffort: true, models: models
    )
  }

  public func complete(_ request: AgentRequest) async throws -> AgentReply {
    try await ProviderRun.withTemporaryFolder(id) { folder in
      let work = folder.appendingPathComponent("work", isDirectory: true)
      let home = folder.appendingPathComponent("home", isDirectory: true)
      let manager = FileManager.default
      try manager.createDirectory(at: work, withIntermediateDirectories: true)
      try manager.createDirectory(at: home, withIntermediateDirectories: true)
      let linkedAuth = home.appendingPathComponent("auth.json")
      if manager.fileExists(atPath: Self.realAuth.path) {
        try manager.createSymbolicLink(at: linkedAuth, withDestinationURL: Self.realAuth)
      }
      let output = folder.appendingPathComponent("last-message.txt")

      var arguments = [
        "exec", "--json", "--ephemeral", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check",
        "-s", "read-only",
        "-c", "developer_instructions=\(Self.tomlString(request.system))",
        "-c", "mcp_servers={}",
        "-c", "project_doc_max_bytes=0",
        // Without this, every skill under ~/.agents/skills is listed in the prompt.
        "-c", "skills.include_instructions=false",
        "-c", #"web_search="disabled""#,
      ]
      for feature in Self.disabledFeatures { arguments += ["--disable", feature] }
      if let model = request.model, !model.isEmpty { arguments += ["-m", model] }
      if request.effort != .automatic {
        arguments += ["-c", "model_reasoning_effort=\(Self.tomlString(request.effort.rawValue))"]
      }
      if let schema = request.jsonSchema {
        let schemaFile = folder.appendingPathComponent("schema.json")
        try Data(schema.utf8).write(to: schemaFile)
        arguments += ["--output-schema", schemaFile.path]
      }
      arguments += ["-o", output.path, "-"]

      let result = try await ProviderRun.launch(
        id: id, provider: name, executable: Self.executable, arguments: arguments, input: request.prompt,
        environment: ["CODEX_HOME": home.path], directory: work, timeout: request.timeout
      )
      Self.keepRefreshedSignIn(linkedAuth)
      let finalMessage = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
      return try parse(result, finalMessage: finalMessage, request: request)
    }
  }

  private func parse(_ result: ShellResult, finalMessage: String, request: AgentRequest) throws -> AgentReply {
    let events = LooseJSON.lines(result.stdout)
    var lastMessage: String?
    var usage: [String: Any] = [:]
    var errors: [String] = []
    for event in events {
      switch event["type"] as? String {
      case "item.completed":
        if let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message" {
          lastMessage = item["text"] as? String
        }
      case "turn.completed":
        usage = event["usage"] as? [String: Any] ?? [:]
      case "error":
        if let message = LooseJSON.errorMessage(event["message"] ?? event["error"]) { errors.append(message) }
      case "turn.failed":
        if let message = LooseJSON.errorMessage(event["error"]) { errors.append(message) }
      default:
        break
      }
    }
    let text = finalMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (lastMessage ?? "") : finalMessage

    if result.status != 0 || (text.isEmpty && !errors.isEmpty) {
      let stderr = result.stderr.replacingOccurrences(of: "Reading additional input from stdin...", with: "")
      let message = errors.last ?? stderr
      ProviderRun.logFailure(provider: id, model: request.model, status: result.status, duration: result.duration, reason: "codex error")
      throw ProviderRun.classify(provider: name, message: message, signInHint: Self.signInHint)
    }
    guard !text.isEmpty else {
      ProviderRun.logFailure(provider: id, model: request.model, status: result.status, duration: result.duration, reason: "empty reply")
      throw AgentError.badReply(provider: name, detail: "Codex finished without a reply.")
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

  /// If Codex refreshed its sign-in during the run, it may have written a new `auth.json`
  /// in place of the link. Move that file back over the original so the person stays
  /// signed in; its contents are never read.
  static func keepRefreshedSignIn(_ linked: URL) {
    let manager = FileManager.default
    guard let attributes = try? manager.attributesOfItem(atPath: linked.path),
          attributes[.type] as? FileAttributeType == .typeRegular,
          // An empty or truncated file would sign the person out, so leave the original.
          (attributes[.size] as? Int ?? 0) > 64
    else { return }
    do {
      _ = try manager.replaceItemAt(realAuth, withItemAt: linked)
      Log.info(.agent, "codex refreshed its sign-in during a run; kept the new one")
    } catch {
      Log.warning(.agent, "codex refreshed its sign-in but it couldn’t be kept: \(error.localizedDescription)")
    }
  }

  /// A TOML basic string, so any system prompt survives `-c key=value` intact.
  static func tomlString(_ value: String) -> String {
    var escaped = "\""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"": escaped += "\\\""
      case "\\": escaped += "\\\\"
      case "\n": escaped += "\\n"
      case "\r": escaped += "\\r"
      case "\t": escaped += "\\t"
      default:
        if scalar.value < 0x20 || scalar.value == 0x7F {
          escaped += String(format: "\\u%04X", scalar.value)
        } else {
          escaped.unicodeScalars.append(scalar)
        }
      }
    }
    return escaped + "\""
  }
}
