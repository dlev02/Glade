import AppKit
import Foundation

public enum AppControlError: Error, LocalizedError, Equatable {
  case notFound(String)
  case ambiguous(String, matches: [String])
  /// Part of macOS, or owned by another user.
  case systemApp(String)
  case isGlade
  /// A running process that isn’t an app, so it can’t be asked to quit.
  case notAnApp(String)
  case relaunchFailed(String, reason: String)

  public var errorDescription: String? {
    switch self {
    case .notFound(let target): "No running app matches “\(target)”."
    case .ambiguous(let target, let matches): "“\(target)” matches more than one app: \(matches.joined(separator: ", "))."
    case .systemApp(let name): "\(name) is part of macOS and isn’t quit by \(Brand.name)."
    case .isGlade: "\(Brand.name) doesn’t quit itself."
    case .notAnApp(let name): "\(name) is a process, not an app, so it can’t be asked to quit."
    case .relaunchFailed(let name, let reason): "\(name) quit but couldn’t be reopened: \(reason)"
    }
  }
}

/// What happened when an app was asked to quit or relaunch.
public struct AppActionResult: Codable, Sendable {
  public enum Action: String, Codable, Sendable {
    case quit, forceQuit, relaunch
  }

  public var action: Action
  public var name: String
  public var bundleIdentifier: String?
  public var pid: Int32
  /// The process was gone before the timeout. A graceful quit can be held up by the app
  /// asking about unsaved work.
  public var exited: Bool
  public var relaunchedPID: Int32?
  public var seconds: Double
  /// One plain sentence describing the outcome.
  public var message: String
}

/// The only actions Glade takes on running apps: ask to quit, force quit when the
/// person explicitly says so, and relaunch. System apps and Glade itself are refused.
public enum AppControl {
  /// Asks the app to quit, as choosing Quit from its menu would. The app may ask about
  /// unsaved work, so `exited` can be `false` when the timeout passes.
  /// - Parameter target: An app id from `AppUsage.id`, a bundle identifier, an app name or a pid.
  public static func quit(_ target: String, timeout: TimeInterval = 10) async throws -> AppActionResult {
    let app = try resolve(target)
    return await terminate(app, force: false, timeout: timeout)
  }

  public static func quit(pid: pid_t, timeout: TimeInterval = 10) async throws -> AppActionResult {
    try await quit(String(pid), timeout: timeout)
  }

  /// Ends the app immediately. Unsaved work is lost, so call this only when the person
  /// has asked for a force quit.
  public static func forceQuit(_ target: String, timeout: TimeInterval = 5) async throws -> AppActionResult {
    let app = try resolve(target)
    return await terminate(app, force: true, timeout: timeout)
  }

  public static func forceQuit(pid: pid_t, timeout: TimeInterval = 5) async throws -> AppActionResult {
    try await forceQuit(String(pid), timeout: timeout)
  }

  /// Quits the app gracefully, waits for it to exit, then opens it again.
  public static func relaunch(_ target: String, timeout: TimeInterval = 15) async throws -> AppActionResult {
    let app = try resolve(target)
    guard let url = app.bundleURL else {
      throw AppControlError.relaunchFailed(app.name, reason: "its location isn’t known")
    }
    let started = Date()
    var result = await terminate(app, force: false, timeout: timeout)
    result.action = .relaunch
    guard result.exited else {
      result.message = "\(app.name) didn’t quit within \(Int(timeout)) seconds, so it wasn’t reopened. It may be asking about unsaved work."
      Log.info(.system, "Relaunch \(app.name): didn’t quit, not reopened")
      return result
    }
    do {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      let reopened = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
      result.relaunchedPID = reopened.processIdentifier
      result.seconds = Date().timeIntervalSince(started)
      result.message = "\(app.name) was relaunched."
      Log.info(.system, "Relaunch \(app.name): reopened as pid \(reopened.processIdentifier) in \(String(format: "%.1f", result.seconds))s")
      return result
    } catch {
      Log.warning(.system, "Relaunch \(app.name): reopening failed: \(error.localizedDescription)")
      throw AppControlError.relaunchFailed(app.name, reason: error.localizedDescription)
    }
  }

  // MARK: Resolution

  struct Target: Sendable {
    var pid: pid_t
    var name: String
    var bundleID: String?
    var bundleURL: URL?
  }

  /// Finds the running app a person or agent means, and refuses ones Glade must not touch.
  static func resolve(_ target: String) throws -> Target {
    let wanted = target.trimmingCharacters(in: .whitespaces)
    let lower = wanted.lowercased()
    let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated && $0.processIdentifier > 0 }

    var matches: [NSRunningApplication]
    if let pid = pid_t(wanted) {
      matches = running.filter { $0.processIdentifier == pid }
      if matches.isEmpty {
        if kill(pid, 0) == 0 || errno == EPERM {
          throw AppControlError.notAnApp(ProcessTable.executablePath(pid).map { ($0 as NSString).lastPathComponent } ?? "pid \(pid)")
        }
        throw AppControlError.notFound(wanted)
      }
    } else {
      let path = lower.hasPrefix("path:") ? String(wanted.dropFirst(5)) : nil
      matches = running.filter {
        $0.bundleIdentifier?.lowercased() == lower || $0.localizedName?.lowercased() == lower
          || (path != nil && $0.bundleURL?.path == path)
      }
      if matches.isEmpty {
        // Allow the bundle’s file name ("Visual Studio Code") or a unique prefix of a name.
        matches = running.filter {
          $0.bundleURL.map { $0.deletingPathExtension().lastPathComponent.lowercased() == lower } ?? false
        }
      }
      if matches.isEmpty {
        let prefixed = running.filter { $0.activationPolicy == .regular && ($0.localizedName?.lowercased().hasPrefix(lower) ?? false) }
        if Set(prefixed.compactMap(\.bundleIdentifier)).count == 1 { matches = prefixed }
      }
    }
    guard let first = matches.first else { throw AppControlError.notFound(wanted) }
    let distinct = Set(matches.map { $0.bundleIdentifier ?? $0.bundleURL?.path ?? String($0.processIdentifier) })
    if distinct.count > 1 {
      throw AppControlError.ambiguous(wanted, matches: matches.map { "\($0.localizedName ?? "?") (\($0.bundleIdentifier ?? String($0.processIdentifier)))" })
    }
    // Several instances of one app: act on the regular one.
    let app = matches.first { $0.activationPolicy == .regular } ?? first
    let name = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? wanted
    let pid = app.processIdentifier

    let gladeBundleID = Bundle.main.bundleIdentifier?.lowercased()
    if pid == getpid() || (gladeBundleID != nil && app.bundleIdentifier?.lowercased() == gladeBundleID)
      || name.caseInsensitiveCompare(Brand.name) == .orderedSame
    {
      Log.info(.system, "Refused to quit \(name): it’s \(Brand.name)")
      throw AppControlError.isGlade
    }
    var owner = proc_bsdshortinfo()
    let size = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
    let otherUser = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &owner, size) == size && owner.pbsi_uid != getuid()
    let path = app.bundleURL?.path ?? app.executableURL?.path
    if otherUser || SystemApps.isSystem(path: path, bundleID: app.bundleIdentifier, name: name) {
      Log.info(.system, "Refused to quit \(name): it’s a system app")
      throw AppControlError.systemApp(name)
    }
    return Target(pid: pid, name: name, bundleID: app.bundleIdentifier, bundleURL: app.bundleURL)
  }

  // MARK: Termination

  private static func terminate(_ target: Target, force: Bool, timeout: TimeInterval) async -> AppActionResult {
    let started = Date()
    let action: AppActionResult.Action = force ? .forceQuit : .quit
    // Look the app up again by pid so no NSRunningApplication crosses an await.
    let asked = NSRunningApplication(processIdentifier: target.pid).map { force ? $0.forceTerminate() : $0.terminate() } ?? false
    let exited = asked ? await waitForExit(target.pid, timeout: timeout) : !isAlive(target.pid)
    let seconds = Date().timeIntervalSince(started)
    let verb = force ? "Force quit" : "Quit"
    let message: String
    if exited {
      message = "\(target.name) quit."
    } else if !asked {
      message = "\(target.name) didn’t accept the request to quit."
    } else if force {
      message = "\(target.name) was told to stop but was still running after \(Int(timeout)) seconds."
    } else {
      message = "\(target.name) was asked to quit but is still open after \(Int(timeout)) seconds. It may be asking about unsaved work."
    }
    Log.info(.system, "\(verb) \(target.name) (pid \(target.pid)): \(exited ? "exited" : asked ? "still running" : "request refused") after \(String(format: "%.1f", seconds))s")
    return AppActionResult(
      action: action, name: target.name, bundleIdentifier: target.bundleID, pid: target.pid,
      exited: exited, relaunchedPID: nil, seconds: seconds, message: message
    )
  }

  /// Polls the pid rather than `isTerminated`, which only updates on a main run loop.
  private static func waitForExit(_ pid: pid_t, timeout: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !isAlive(pid) { return true }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return !isAlive(pid)
  }

  private static func isAlive(_ pid: pid_t) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
  }
}
