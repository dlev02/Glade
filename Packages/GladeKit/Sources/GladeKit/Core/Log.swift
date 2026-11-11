import Foundation
import os

/// The areas of the app that write to the log. One per boundary that can fail or surprise.
public enum LogCategory: String, Codable, Sendable, CaseIterable {
  case app, cli, scan, clean, safety, system, agent, automation, index, update, mcp
}

public enum LogLevel: String, Codable, Sendable, Comparable {
  case debug, info, warning, error

  private var rank: Int {
    switch self {
    case .debug: 0
    case .info: 1
    case .warning: 2
    case .error: 3
    }
  }

  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }
}

public struct LogEntry: Codable, Sendable, Identifiable {
  public var id: UUID
  public var date: Date
  public var level: LogLevel
  public var category: LogCategory
  public var message: String

  public var line: String {
    let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    return "\(stamp) \(level.rawValue.uppercased().padding(toLength: 7, withPad: " ", startingAt: 0)) [\(category.rawValue)] \(message)"
  }
}

/// The single logging helper. Every line goes to the unified system log, an in-memory
/// ring, and a small rotating file under ~/Library/Logs, with secrets and the home
/// folder’s name scrubbed before anything is stored.
public enum Log {
  public static func debug(_ category: LogCategory, _ message: @autoclosure () -> String) {
    store.write(.debug, category, message())
  }

  public static func info(_ category: LogCategory, _ message: @autoclosure () -> String) {
    store.write(.info, category, message())
  }

  public static func warning(_ category: LogCategory, _ message: @autoclosure () -> String) {
    store.write(.warning, category, message())
  }

  public static func error(_ category: LogCategory, _ message: @autoclosure () -> String) {
    store.write(.error, category, message())
  }

  /// The newest entries, oldest first.
  public static func recent(limit: Int = 400, minimum: LogLevel = .debug) -> [LogEntry] {
    store.recent(limit: limit, minimum: minimum)
  }

  /// Entries from this run and earlier ones, read back from the log files.
  public static func history(limit: Int = 2000) -> [LogEntry] {
    store.history(limit: limit)
  }

  /// Waits until everything logged so far is on disk. Call before the process exits.
  public static func flush() {
    store.flush()
  }

  /// Echo warnings and errors to stderr. The command line turns this on.
  public static func echoToStandardError(minimum: LogLevel?) {
    store.setEcho(minimum)
  }

  static let store = LogStore()
}

final class LogStore: @unchecked Sendable {
  private let queue = DispatchQueue(label: "glade.log", qos: .utility)
  private var ring: [LogEntry] = []
  private let ringLimit = 1000
  private let fileLimit = 1_500_000
  private var handle: FileHandle?
  private var echo: LogLevel?
  private let loggers: [LogCategory: Logger]
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  init() {
    let subsystem = Bundle.main.bundleIdentifier ?? "glade"
    loggers = Dictionary(uniqueKeysWithValues: LogCategory.allCases.map {
      ($0, Logger(subsystem: subsystem, category: $0.rawValue))
    })
  }

  /// Test runs log to a scratch folder so they don’t fill the real log.
  private let folder: URL = {
    let name = ProcessInfo.processInfo.processName.lowercased()
    if name.contains("xctest") || name.contains("testing-helper") {
      return FileManager.default.temporaryDirectory.appendingPathComponent("glade-test-logs", isDirectory: true)
    }
    return GladePaths.logs
  }()

  private var currentFile: URL { folder.appendingPathComponent("glade.log") }
  private var previousFile: URL { folder.appendingPathComponent("glade.1.log") }

  func flush() {
    queue.sync {}
  }

  func setEcho(_ level: LogLevel?) {
    queue.sync { echo = level }
  }

  func write(_ level: LogLevel, _ category: LogCategory, _ raw: String) {
    let message = Redactor.scrub(raw)
    let entry = LogEntry(id: UUID(), date: Date(), level: level, category: category, message: message)
    let logger = loggers[category]
    switch level {
    case .debug: logger?.debug("\(message, privacy: .public)")
    case .info: logger?.info("\(message, privacy: .public)")
    case .warning: logger?.warning("\(message, privacy: .public)")
    case .error: logger?.error("\(message, privacy: .public)")
    }
    queue.async { [self] in
      ring.append(entry)
      if ring.count > ringLimit { ring.removeFirst(ring.count - ringLimit) }
      if let echo, level >= echo {
        FileHandle.standardError.write(Data("\(Brand.cli): \(level.rawValue): \(message)\n".utf8))
      }
      append(entry)
    }
  }

  func recent(limit: Int, minimum: LogLevel) -> [LogEntry] {
    queue.sync { Array(ring.filter { $0.level >= minimum }.suffix(limit)) }
  }

  func history(limit: Int) -> [LogEntry] {
    queue.sync {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      var entries: [LogEntry] = []
      for file in [previousFile, currentFile] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for line in text.split(separator: "\n") {
          if let entry = try? decoder.decode(LogEntry.self, from: Data(line.utf8)) { entries.append(entry) }
        }
      }
      return Array(entries.suffix(limit))
    }
  }

  private func append(_ entry: LogEntry) {
    guard var data = try? encoder.encode(entry) else { return }
    data.append(0x0A)
    if handle == nil { open() }
    guard let handle else { return }
    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      if try handle.offset() > UInt64(fileLimit) { rotate() }
    } catch {
      self.handle = nil
    }
  }

  private func open() {
    let manager = FileManager.default
    try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
    if !manager.fileExists(atPath: currentFile.path) {
      manager.createFile(atPath: currentFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    handle = try? FileHandle(forWritingTo: currentFile)
  }

  private func rotate() {
    try? handle?.close()
    handle = nil
    let manager = FileManager.default
    try? manager.removeItem(at: previousFile)
    try? manager.moveItem(at: currentFile, to: previousFile)
  }
}

/// Removes things that should never be written down: credentials, and the account
/// name embedded in every path under the home folder.
public enum Redactor {
  private static let home = NSHomeDirectory()

  private static let patterns: [NSRegularExpression] = [
    #"(?i)\b(sk|pk|rk)-[a-z0-9_\-]{16,}"#,
    #"\bgh[pousr]_[A-Za-z0-9]{20,}"#,
    #"\bgithub_pat_[A-Za-z0-9_]{20,}"#,
    #"\bxox[abprs]-[A-Za-z0-9\-]{10,}"#,
    #"\bAKIA[0-9A-Z]{16}\b"#,
    #"(?i)\bbearer\s+[a-z0-9._\-]{16,}"#,
    #"(?i)\b(api[_-]?key|token|secret|password|passwd|authorization)(["']?\s*[:=]\s*["']?)[^\s"',;]{6,}"#,
    #"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{6,}"#,
  ].compactMap { try? NSRegularExpression(pattern: $0) }

  public static func scrub(_ text: String) -> String {
    var result = text.replacingOccurrences(of: home, with: "~")
    for pattern in patterns {
      let range = NSRange(result.startIndex..., in: result)
      result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: "‹redacted›")
    }
    return result
  }

  /// A path with the home folder shortened to `~`, for display and for prompts.
  public static func tilde(_ path: String) -> String {
    path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }
}
