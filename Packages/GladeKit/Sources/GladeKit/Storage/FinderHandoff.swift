import Foundation

/// Asks Finder to move an app to the Trash, or back out of it, when macOS needs the
/// person’s password for that app (most App Store and installer apps belong to the
/// system). Finder shows its own password or Touch ID prompt; Glade never sees or
/// asks for the password. Used only for an app bundle `Cleaner` has already checked.
///
/// Paths reach `osascript` as arguments, never inside the script’s text.
enum FinderHandoff {
  enum Failure: Error, Equatable {
    /// The person dismissed Finder’s password prompt.
    case cancelled
    /// Glade isn’t allowed to control Finder (Privacy & Security › Automation).
    case notAllowed
    case other(String)

    var reason: String {
      switch self {
      case .cancelled: "You cancelled the password prompt, so it stayed."
      case .notAllowed: "Glade isn’t allowed to control Finder. Turn it on in System Settings › Privacy & Security › Automation."
      case .other(let text): text
      }
    }
  }

  /// Long enough for the person to notice Finder’s prompt and answer it.
  static let timeout: TimeInterval = 300

  static let trashScript = """
    on run argv
      tell application "Finder" to set moved to delete (POSIX file (item 1 of argv) as alias)
      return POSIX path of (moved as alias)
    end run
    """

  static let moveScript = """
    on run argv
      tell application "Finder" to set moved to move (POSIX file (item 1 of argv) as alias) to (POSIX file (item 2 of argv) as alias)
      return POSIX path of (moved as alias)
    end run
    """

  /// Moves `path` to the Trash through Finder.
  /// - Returns: Where it is in the Trash.
  static func trash(_ path: String) async -> Result<String, Failure> {
    await run(trashScript, [path], what: "move \(Redactor.tilde(path)) to the Trash")
  }

  /// Moves `path` into `folder` through Finder, for putting an app back.
  /// - Returns: Where it is now.
  static func move(_ path: String, into folder: String) async -> Result<String, Failure> {
    await run(moveScript, [path, folder], what: "put back \(Redactor.tilde(path))")
  }

  private static func run(_ script: String, _ arguments: [String], what: String) async -> Result<String, Failure> {
    Log.info(.clean, "Asking Finder to \(what)")
    do {
      let result = try await Shell.run("/usr/bin/osascript", ["-e", script] + arguments, timeout: timeout, quiet: true)
      if result.succeeded {
        var moved = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if moved.count > 1, moved.hasSuffix("/") { moved.removeLast() }
        return .success(moved)
      }
      let failure = failure(from: result.stderr)
      Log.warning(.clean, "Finder couldn’t \(what): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
      return .failure(failure)
    } catch {
      Log.warning(.clean, "Finder couldn’t \(what): \(error)")
      return .failure(.other(error.localizedDescription))
    }
  }

  /// Reads `osascript`’s error, which ends with the Apple Event error number.
  static func failure(from stderr: String) -> Failure {
    if stderr.contains("(-128)") { return .cancelled }
    if stderr.contains("(-1743)") || stderr.contains("(-10004)") { return .notAllowed }
    if stderr.contains("(-1712)") { return .other("Finder’s password prompt wasn’t answered in time.") }
    let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"^.*execution error: "#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s*\(-?\d+\)$"#, with: "", options: .regularExpression)
    return .other(text.isEmpty ? "Finder couldn’t move it." : text)
  }
}
