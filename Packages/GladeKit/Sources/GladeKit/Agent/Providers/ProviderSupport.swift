import Foundation

/// Helpers every command-line provider shares: a throwaway working folder, one guarded
/// process launch per request, a cache for versions and model lists, and the mapping from
/// a tool's error text to `AgentError`.
enum ProviderRun {
  /// Runs `body` with a fresh, empty folder that's deleted afterwards, whatever happens.
  static func withTemporaryFolder<T: Sendable>(_ label: String, _ body: (URL) async throws -> T) async throws -> T {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("glade-\(label)-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: folder) }
    return try await body(folder)
  }

  /// Launches the tool once. A missing binary becomes `.notInstalled` and running past the
  /// timeout becomes `.timedOut`; there is never a retry.
  static func launch(
    id: String,
    provider: String,
    executable: String,
    arguments: [String],
    input: String,
    environment: [String: String]? = nil,
    directory: URL,
    timeout: TimeInterval
  ) async throws -> ShellResult {
    // Some tools (OpenCode) take the folder from PWD rather than the real working
    // directory, which would otherwise still be the folder Glade was started from.
    var merged = environment ?? [:]
    merged["PWD"] = directory.path
    let result: ShellResult
    do {
      result = try await Shell.run(executable, arguments, input: input, environment: merged, directory: directory.path, timeout: max(1, timeout))
    } catch ShellError.notFound {
      throw AgentError.notInstalled(provider: provider)
    } catch let error as ShellError {
      throw AgentError.failed(provider: provider, detail: error.localizedDescription)
    }
    if result.timedOut {
      logFailure(provider: id, status: result.status, duration: result.duration, reason: "timed out")
      throw AgentError.timedOut(provider: provider, seconds: Int(timeout.rounded()))
    }
    return result
  }

  /// The system prompt and prompt as one text, for tools with no way to pass a system
  /// prompt separately.
  static func combined(system: String, prompt: String) -> String {
    guard !system.isEmpty else { return prompt }
    return "<instructions>\n\(system)\n</instructions>\n\nFollow the instructions above. The request follows.\n\n\(prompt)"
  }

  /// The one line written for each completed request. Never includes prompt or reply text.
  static func logSuccess(_ reply: AgentReply, status: Int32 = 0) {
    var parts = ["\(reply.provider) model=\(reply.model ?? "default") exit=\(status) in \(String(format: "%.1f", reply.duration))s"]
    if let input = reply.inputTokens { parts.append("in=\(input)") }
    if let output = reply.outputTokens { parts.append("out=\(output)") }
    if let cost = reply.costUSD { parts.append(String(format: "cost=$%.4f", cost)) }
    Log.info(.agent, parts.joined(separator: " "))
  }

  static func logFailure(provider: String, model: String? = nil, status: Int32, duration: TimeInterval, reason: String) {
    Log.info(.agent, "\(provider) model=\(model ?? "default") exit=\(status) in \(String(format: "%.1f", duration))s failed: \(reason)")
  }

  /// Turns a tool's own error message into the closest `AgentError`.
  static func classify(provider: String, message: String, signInHint: String) -> AgentError {
    let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = text.lowercased()
    let limits = ["rate limit", "rate_limit", "ratelimit", "429", "quota", "usage limit", "too many requests", "limit reached", "credit balance", "insufficient credits", "out of credits", "resource_exhausted", "resource exhausted", "hit your limit"]
    if limits.contains(where: lower.contains) {
      return .rateLimited(provider: provider, detail: excerpt(text))
    }
    let auth = ["not logged in", "not signed in", "please log in", "please login", "please sign in", "sign in", "log in to", "login required", "unauthorized", "401", "authentication", "invalid api key", "invalid x-api-key", "api key not", "auth method", "oauth token", "token expired", "credentials"]
    if auth.contains(where: lower.contains) {
      return .notSignedIn(provider: provider, hint: signInHint)
    }
    return .failed(provider: provider, detail: excerpt(text.isEmpty ? "It stopped without saying why." : text))
  }

  /// The first ~300 characters of an error, on one line.
  static func excerpt(_ text: String, limit: Int = 300) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
  }

  /// Whether a file or symlink exists. Used for sign-in markers: never opened or read.
  static func exists(_ path: String) -> Bool {
    let expanded = path.hasPrefix("~/") ? NSHomeDirectory() + path.dropFirst(1) : path
    return FileManager.default.fileExists(atPath: expanded)
  }

  static func environmentHas(_ names: [String]) -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return names.contains { !(environment[$0] ?? "").isEmpty }
  }

  /// Whether the login keychain holds a generic password with this service (and account).
  /// Checks the exit status only; the secret is never requested.
  static func keychainHas(service: String, account: String? = nil) async -> Bool {
    var arguments = ["find-generic-password", "-s", service]
    if let account { arguments += ["-a", account] }
    let result = try? await Shell.run("/usr/bin/security", arguments, timeout: 2, quiet: true)
    return result?.succeeded == true
  }
}

/// Values that are slow to learn and don't change while the app runs: tool versions,
/// model lists, one-off probe results.
final class ProviderCache: @unchecked Sendable {
  static let shared = ProviderCache()

  private let lock = NSLock()
  private var values: [String: [String]] = [:]

  func value(_ key: String) -> [String]? { lock.withLock { values[key] } }
  func set(_ key: String, _ value: [String]) { lock.withLock { values[key] = value } }

  /// The tool's version, read once per binary path with `--version`.
  func version(of path: String, arguments: [String] = ["--version"]) async -> String? {
    let key = "version:\(path)"
    if let cached = value(key) { return cached.first }
    guard let result = try? await Shell.run(path, arguments, timeout: 3, quiet: true), result.succeeded else { return nil }
    let version = Self.versionNumber(in: result.stdout + "\n" + result.stderr)
    set(key, version.map { [$0] } ?? [])
    return version
  }

  /// Model names from a listing command, read once. `parse` turns its output into names.
  func models(_ key: String, executable: String, arguments: [String], environment: [String: String]? = nil, parse: @Sendable (String) -> [String]) async -> [String] {
    let cacheKey = "models:\(key)"
    if let cached = value(cacheKey) { return cached }
    guard let result = try? await Shell.run(executable, arguments, environment: environment, timeout: 2.5, quiet: true), result.succeeded else { return [] }
    let names = parse(result.stdout)
    set(cacheKey, names)
    return names
  }

  static func versionNumber(in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"\d+(\.\d+)+([\w.\-]*)"#) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range), let swiftRange = Range(match.range, in: text) else { return nil }
    return String(text[swiftRange])
  }
}

/// Small readers for the loosely typed JSON the tools print.
enum LooseJSON {
  static func object(_ text: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
  }

  /// Each line of JSON Lines output that parses as an object.
  static func lines(_ text: String) -> [[String: Any]] {
    text.split(whereSeparator: \.isNewline).compactMap { object(String($0)) }
  }

  static func int(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    return nil
  }

  static func double(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    return nil
  }

  static func string(_ object: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  /// A message from an `error` field that may be a string or an object with `message`.
  static func errorMessage(_ value: Any?) -> String? {
    if let text = value as? String { return text }
    if let object = value as? [String: Any] {
      if let message = object["message"] as? String { return message }
      if let data = object["data"] as? [String: Any], let message = data["message"] as? String { return message }
      if let nested = object["error"] { return errorMessage(nested) }
      return string(object)
    }
    return nil
  }
}
