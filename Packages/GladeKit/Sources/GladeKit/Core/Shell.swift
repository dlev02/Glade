import Foundation

public struct ShellResult: Sendable {
  public var status: Int32
  public var stdout: String
  public var stderr: String
  public var duration: TimeInterval
  public var timedOut: Bool

  public var succeeded: Bool { status == 0 && !timedOut }
}

public enum ShellError: Error, LocalizedError {
  case notFound(String)
  case launchFailed(String, String)

  public var errorDescription: String? {
    switch self {
    case .notFound(let name): "\(name) isn’t installed or couldn’t be found."
    case .launchFailed(let name, let reason): "\(name) couldn’t be started: \(reason)"
    }
  }
}

/// Runs other programs. Every external command Glade launches goes through here, so
/// each one is logged with its exit status and duration.
public enum Shell {
  /// Folders searched for command-line tools. Apps launched from the Dock don’t inherit
  /// the shell’s PATH, so the usual install locations are listed explicitly.
  public static var searchPaths: [String] {
    let home = NSHomeDirectory()
    let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    let common = [
      "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.bun/bin",
      "\(home)/.npm-global/bin", "\(home)/.cargo/bin", "\(home)/.volta/bin", "\(home)/bin",
      "\(home)/.opencode/bin", "\(home)/.codex/bin", "\(home)/.claude/local",
      "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]
    var seen = Set<String>()
    return (inherited + common).filter { seen.insert($0).inserted }
  }

  public static func which(_ name: String) -> String? {
    if name.contains("/") {
      return FileManager.default.isExecutableFile(atPath: name) ? name : nil
    }
    for folder in searchPaths {
      let candidate = "\(folder)/\(name)"
      if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
  }

  /// Runs a program to completion and collects its output.
  /// - Parameters:
  ///   - timeout: Seconds before the program is terminated. `nil` waits forever.
  ///   - quiet: Skip the log line, for commands that run every few seconds.
  public static func run(
    _ executable: String,
    _ arguments: [String] = [],
    input: String? = nil,
    environment: [String: String]? = nil,
    directory: String? = nil,
    timeout: TimeInterval? = 30,
    quiet: Bool = false
  ) async throws -> ShellResult {
    guard let path = which(executable) else { throw ShellError.notFound(executable) }
    let started = Date()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    var merged = ProcessInfo.processInfo.environment
    merged["PATH"] = searchPaths.joined(separator: ":")
    if let environment { merged.merge(environment) { _, new in new } }
    process.environment = merged
    if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }

    let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.standardInput = input == nil ? FileHandle.nullDevice : inPipe

    let state = RunState()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellResult, Error>) in
        let group = DispatchGroup()
        let reader = DispatchQueue(label: "glade.shell.read", attributes: .concurrent)
        group.enter()
        reader.async {
          state.setOut(outPipe.fileHandleForReading.readDataToEndOfFile())
          group.leave()
        }
        group.enter()
        reader.async {
          state.setErr(errPipe.fileHandleForReading.readDataToEndOfFile())
          group.leave()
        }
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
          try process.run()
        } catch {
          process.terminationHandler = nil
          group.leave()
          try? outPipe.fileHandleForWriting.close()
          try? errPipe.fileHandleForWriting.close()
          continuation.resume(throwing: ShellError.launchFailed(executable, error.localizedDescription))
          return
        }
        state.setProcess(process)

        if let input {
          reader.async {
            let writer = inPipe.fileHandleForWriting
            try? writer.write(contentsOf: Data(input.utf8))
            try? writer.close()
          }
        }
        if let timeout {
          DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning {
              state.markTimedOut()
              process.terminate()
              DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
              }
            }
          }
        }
        group.notify(queue: .global()) {
          let result = ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: state.out, as: UTF8.self),
            stderr: String(decoding: state.err, as: UTF8.self),
            duration: Date().timeIntervalSince(started),
            timedOut: state.timedOut
          )
          if !quiet {
            let name = (path as NSString).lastPathComponent
            let summary = "\(name) \(arguments.prefix(4).joined(separator: " ")) → exit \(result.status) in \(String(format: "%.1f", result.duration))s"
            if result.timedOut {
              Log.warning(.system, "\(summary) (timed out after \(Int(timeout ?? 0))s)")
            } else if result.status != 0 {
              Log.warning(.system, "\(summary): \(result.stderr.prefix(300))")
            } else {
              Log.debug(.system, summary)
            }
          }
          continuation.resume(returning: result)
        }
      }
    } onCancel: {
      state.terminate()
    }
  }
}

private final class RunState: @unchecked Sendable {
  private let lock = NSLock()
  private var _out = Data(), _err = Data()
  private var _timedOut = false
  private var process: Process?

  var out: Data { lock.withLock { _out } }
  var err: Data { lock.withLock { _err } }
  var timedOut: Bool { lock.withLock { _timedOut } }

  func setOut(_ data: Data) { lock.withLock { _out = data } }
  func setErr(_ data: Data) { lock.withLock { _err = data } }
  func markTimedOut() { lock.withLock { _timedOut = true } }
  func setProcess(_ process: Process) { lock.withLock { self.process = process } }

  func terminate() {
    let running = lock.withLock { process }
    if let running, running.isRunning { running.terminate() }
  }
}
