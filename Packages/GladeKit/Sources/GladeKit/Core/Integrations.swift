import Foundation

/// The `glade` command in Terminal. Glade’s own executable doubles as the command when
/// it’s started through a symbolic link named `glade`, so installing it only places
/// that link in a folder on the shell’s search path. Nothing here asks for a password.
public enum CommandLineTool {
  public enum Status: Sendable, Equatable {
    /// Glade isn’t running from an installed app, so there’s nothing to link to.
    case unavailable
    case notInstalled
    /// - Parameter onPath: The folder is on the shell’s search path, so typing `glade` works.
    case installed(path: String, onPath: Bool)
    /// A link from an older or different copy of Glade.
    case otherCopy(path: String, target: String)
    /// Something else named `glade` is already there and is left alone.
    case occupied(path: String)

    public var isInstalled: Bool {
      if case .installed = self { return true }
      return false
    }
  }

  public enum Failure: Error, LocalizedError, Sendable {
    case notAnApp
    case occupied(String)
    case failed(String)

    public var errorDescription: String? {
      switch self {
      case .notAnApp: "The command line tool is available after installing the app."
      case .occupied(let path): "Something else named “\(Brand.cli)” is already at \(Redactor.tilde(path))."
      case .failed(let reason): reason
      }
    }
  }

  /// The executable the link points at, or `nil` when Glade isn’t running from an `.app`.
  public static var appExecutable: String? {
    guard Bundle.main.bundlePath.hasSuffix(".app"), let path = Bundle.main.executablePath else { return nil }
    return path
  }

  /// Where the link may go: the person’s own folder first, then the shared one if it
  /// can be written without asking for a password.
  static var folders: [String] {
    var folders = [NSHomeDirectory() + "/.local/bin"]
    if FileManager.default.isWritableFile(atPath: "/usr/local/bin") { folders.append("/usr/local/bin") }
    return folders
  }

  public static func status() async -> Status {
    guard let executable = appExecutable else { return .unavailable }
    let searchPath = await shellSearchPath()
    var found: Status?
    for folder in [NSHomeDirectory() + "/.local/bin", "/usr/local/bin"] {
      let link = folder + "/" + Brand.cli
      switch inspect(link, executable: executable) {
      case .ours: return .installed(path: link, onPath: searchPath.contains(folder))
      case .otherGlade(let target): found = found ?? .otherCopy(path: link, target: target)
      case .foreign: found = found ?? .occupied(path: link)
      case .missing: continue
      }
    }
    return found ?? .notInstalled
  }

  /// Creates the link and returns where it went.
  @discardableResult
  public static func install() async throws -> String {
    guard let executable = appExecutable else { throw Failure.notAnApp }
    let searchPath = await shellSearchPath()
    // A folder the shell already searches is better than one the person has to add.
    let candidates = folders.sorted { searchPath.contains($0) && !searchPath.contains($1) }
    var lastError: Error = Failure.failed("No folder for the link could be written.")
    for folder in candidates {
      let link = folder + "/" + Brand.cli
      switch inspect(link, executable: executable) {
      case .ours:
        Log.info(.app, "Command line tool already installed at \(Redactor.tilde(link))")
        return link
      case .foreign:
        lastError = Failure.occupied(link)
        continue
      case .otherGlade, .missing:
        break
      }
      do {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        if case .otherGlade = inspect(link, executable: executable) {
          try FileManager.default.removeItem(atPath: link)
        }
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: executable)
        Log.info(.app, "Installed the command line tool at \(Redactor.tilde(link))")
        return link
      } catch {
        Log.warning(.app, "Couldn’t install the command line tool at \(Redactor.tilde(link)): \(error.localizedDescription)")
        lastError = Failure.failed(error.localizedDescription)
      }
    }
    throw lastError
  }

  /// Removes the link, but only a link that leads into a copy of Glade.
  public static func remove() async throws {
    guard let executable = appExecutable else { throw Failure.notAnApp }
    for folder in [NSHomeDirectory() + "/.local/bin", "/usr/local/bin"] {
      let link = folder + "/" + Brand.cli
      switch inspect(link, executable: executable) {
      case .ours, .otherGlade:
        do {
          try FileManager.default.removeItem(atPath: link)
          Log.info(.app, "Removed the command line tool from \(Redactor.tilde(link))")
        } catch {
          Log.warning(.app, "Couldn’t remove \(Redactor.tilde(link)): \(error.localizedDescription)")
          throw Failure.failed(error.localizedDescription)
        }
      case .foreign, .missing:
        continue
      }
    }
  }

  private enum Occupant {
    case missing, ours, otherGlade(String), foreign
  }

  private static func inspect(_ link: String, executable: String) -> Occupant {
    let files = FileManager.default
    guard let destination = try? files.destinationOfSymbolicLink(atPath: link) else {
      return files.fileExists(atPath: link) ? .foreign : .missing
    }
    let absolute = destination.hasPrefix("/") ? destination : ((link as NSString).deletingLastPathComponent as NSString).appendingPathComponent(destination)
    let resolved = URL(fileURLWithPath: absolute).resolvingSymlinksInPath().path
    let mine = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
    if resolved == mine { return .ours }
    // Another copy of Glade: a link into an app bundle whose name starts with Glade.
    let isGlade = absolute.components(separatedBy: "/").contains { $0.hasPrefix(Brand.name) && $0.hasSuffix(".app") }
    return isGlade ? .otherGlade(absolute) : .foreign
  }

  /// The folders the person’s login shell searches. Apps started from the Dock don’t
  /// inherit it, so it’s asked for directly.
  static func shellSearchPath() async -> [String] {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let marker = "__GLADE_PATH__"
    // Start from the bare system path so only what the shell’s own startup files add counts.
    guard let result = try? await Shell.run(
      shell, ["-l", "-i", "-c", "printf '\(marker)%s\(marker)' \"$PATH\""],
      environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"], timeout: 5, quiet: true
    ),
          let range = result.stdout.range(of: marker),
          let end = result.stdout.range(of: marker, range: range.upperBound..<result.stdout.endIndex)
    else { return [] }
    return result.stdout[range.upperBound..<end.lowerBound].split(separator: ":").map(String.init)
  }
}

/// Lets coding agents use Glade as a set of tools, by registering Glade’s MCP server
/// with them. It only ever runs the agents' own documented `mcp add`, `remove` and
/// `get` commands; their settings files are protected and never edited directly.
public enum AgentConnection {
  public enum Agent: String, CaseIterable, Identifiable, Sendable {
    case claude, codex

    public var id: String { rawValue }

    public var title: String {
      switch self {
      case .claude: "Claude Code"
      case .codex: "Codex"
      }
    }

    public var executable: String { rawValue }
  }

  public enum State: Sendable, Equatable {
    case notInstalled
    case notConnected
    case connected
    /// Registered, but to a different copy of Glade.
    case connectedElsewhere(command: String)
    case unavailable(reason: String)
  }

  /// The name Glade’s server is registered under.
  public static let serverName = Brand.cli

  /// The program the agent should start: this copy of Glade. `nil` outside an installed app.
  public static var gladeExecutable: String? { CommandLineTool.appExecutable }

  public static func addArguments(_ agent: Agent, executable: String) -> [String] {
    switch agent {
    case .claude: ["mcp", "add", "--scope", "user", serverName, "--", executable, "mcp"]
    case .codex: ["mcp", "add", serverName, "--", executable, "mcp"]
    }
  }

  public static func removeArguments(_ agent: Agent) -> [String] {
    switch agent {
    case .claude: ["mcp", "remove", "--scope", "user", serverName]
    case .codex: ["mcp", "remove", serverName]
    }
  }

  public static func getArguments(_ agent: Agent) -> [String] {
    switch agent {
    case .claude: ["mcp", "get", serverName]
    case .codex: ["mcp", "get", serverName, "--json"]
    }
  }

  /// The command that connects the agent, as typed in Terminal, for showing and copying.
  public static func commandLine(_ agent: Agent, executable: String? = gladeExecutable) -> String {
    let path = executable ?? "/Applications/\(Brand.name).app/Contents/MacOS/\(Brand.name)"
    return ([agent.executable] + addArguments(agent, executable: path)).map(quoted).joined(separator: " ")
  }

  public static func state(_ agent: Agent) async -> State {
    guard Shell.which(agent.executable) != nil else { return .notInstalled }
    do {
      let result = try await Shell.run(agent.executable, getArguments(agent), directory: NSHomeDirectory(), timeout: 20, quiet: true)
      Log.debug(.mcp, "\(agent.executable) \(getArguments(agent).joined(separator: " ")) → exit \(result.status)")
      if result.timedOut { return .unavailable(reason: "\(agent.title) didn’t answer.") }
      guard result.status == 0 else { return .notConnected }
      guard let command = registeredCommand(agent, output: result.stdout) else { return .connected }
      if let mine = gladeExecutable, resolve(command) == resolve(mine) { return .connected }
      return .connectedElsewhere(command: command)
    } catch {
      return .unavailable(reason: error.localizedDescription)
    }
  }

  public static func connect(_ agent: Agent) async throws {
    guard let executable = gladeExecutable else { throw CommandLineTool.Failure.notAnApp }
    if case .connectedElsewhere = await state(agent) {
      _ = try? await run(agent, removeArguments(agent))
    }
    try await run(agent, addArguments(agent, executable: executable))
    Log.info(.mcp, "Connected \(agent.title) to Glade’s tools")
  }

  public static func disconnect(_ agent: Agent) async throws {
    try await run(agent, removeArguments(agent))
    Log.info(.mcp, "Disconnected \(agent.title) from Glade’s tools")
  }

  private static func run(_ agent: Agent, _ arguments: [String]) async throws {
    let result = try await Shell.run(agent.executable, arguments, directory: NSHomeDirectory(), timeout: 30)
    guard result.succeeded else {
      let detail = (result.stderr.isEmpty ? result.stdout : result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
      Log.warning(.mcp, "\(agent.executable) \(arguments.prefix(2).joined(separator: " ")) failed: \(detail.prefix(300))")
      throw CommandLineTool.Failure.failed(detail.isEmpty ? "\(agent.title) couldn’t make the change." : String(detail.prefix(300)))
    }
  }

  /// The program the agent starts for Glade’s server, read from its `get` output.
  static func registeredCommand(_ agent: Agent, output: String) -> String? {
    switch agent {
    case .claude:
      for line in output.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("Command:") {
          return trimmed.dropFirst("Command:".count).trimmingCharacters(in: .whitespaces)
        }
      }
      return nil
    case .codex:
      guard let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let transport = object["transport"] as? [String: Any]
      else { return nil }
      return transport["command"] as? String
    }
  }

  private static func resolve(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
  }

  private static func quoted(_ word: String) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:@"))
    if word.unicodeScalars.allSatisfy(safe.contains) { return word }
    return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
