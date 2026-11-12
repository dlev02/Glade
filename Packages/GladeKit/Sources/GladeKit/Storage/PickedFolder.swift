import Foundation

/// A folder or file the person picked by hand in the whole-disk view, turned into a
/// finding so the cleaner removes it the usual way: by identifier, checked again at the
/// moment of removal, with a receipt and Put Back.
///
/// This exists for the window only. The command line and the MCP server never offer
/// it, so an agent can’t name a path for Glade to remove; and a picked finding is never
/// saved with the scan (`ScanEngine.save` leaves it out).
public enum PickedFolder {
  public static let ruleID = "picked.by-person"
  /// Marks a scan made only to hold a picked finding, which is never saved.
  public static let scanPrefix = "picked-"

  /// Whether a path could be picked, and why not.
  public enum Assessment: Sendable, Equatable {
    case allowed
    case refused(String)
  }

  /// The plain-words answer for a path, without measuring it.
  public static func assess(_ path: String, protection: Protection) -> Assessment {
    let verdict = protection.verdict(forRemoving: path)
    return verdict.isAllowed ? .allowed : .refused(reason(verdict, path: path, protection: protection))
  }

  /// The reason a picked path can’t go, in words a person understands.
  static func reason(_ verdict: Verdict, path: String, protection: Protection) -> String {
    let cleaned = Protection.clean(path)
    switch verdict {
    case .allowed: return "Allowed"
    case .protected(_, let title), .containsProtected(_, let title): return "Protected: \(title)"
    case .structural: return "A folder other things depend on"
    case .repository: return "A project with version history"
    case .otherVolume: return "On another disk"
    case .escapesViaLink: return "A link to somewhere else"
    case .outOfScope:
      if protection.applicationFolders.contains(where: { cleaned == $0 || cleaned.hasPrefix($0 + "/") }) {
        return "Apps are removed with Uninstall"
      }
      if cleaned.hasPrefix("/System") || cleaned == "/usr" || cleaned.hasPrefix("/usr/") && !cleaned.hasPrefix("/usr/local")
        || cleaned.hasPrefix("/private/var/db") || cleaned.hasPrefix("/Library/Apple") {
        return "Part of macOS"
      }
      return cleaned.hasPrefix(protection.home + "/") ? "A folder other things depend on" : "Needs an administrator"
    case .notAnApp, .outsideApplications, .partOfMacOS, .isGlade: return verdict.explanation
    }
  }

  /// The finding for a picked path, measured now, or the reason it can’t be one.
  public static func finding(for rawPath: String, protection: Protection) -> Result<Finding, PickError> {
    let path = Protection.clean(rawPath)
    let verdict = protection.verdict(forRemoving: path)
    guard verdict.isAllowed else {
      Log.info(.safety, "Picked \(Redactor.tilde(path)) refused: \(verdict.explanation)")
      return .failure(PickError(reason: reason(verdict, path: path, protection: protection)))
    }
    var info = stat()
    guard lstat(path, &info) == 0 else { return .failure(PickError(reason: "It’s no longer there.")) }
    let measure = DiskWalk.measure([path], protection: protection)
    var blockers: [Blocker] = []
    if measure.containsStrict {
      blockers.append(Blocker(.inUse, "Holds a library or backup that must stay whole."))
    }
    let name = (path as NSString).lastPathComponent
    let isFolder = (info.st_mode & S_IFMT) == S_IFDIR
    let finding = Finding(
      id: Finding.makeID(rule: ruleID, path: path), ruleID: ruleID, category: .largeFiles, title: name,
      detail: isFolder ? "A folder you chose. It goes to the Trash, so you can put it back." : "A file you chose. It goes to the Trash, so you can put it back.",
      paths: [path], bytes: measure.bytes, fileCount: measure.files, lastUsed: measure.lastUsed,
      recovery: .permanent, risk: .personal, blockers: blockers, method: .trash,
      evidence: ["You picked this in What’s on This Disk."], autoLevel: nil, idleDaysRequired: 0
    )
    Log.info(.clean, "Picked \(Redactor.tilde(path)) to remove: \(Format.bytes(measure.bytes))")
    return .success(finding)
  }

  public struct PickError: Error, Sendable, Equatable {
    public var reason: String
  }
}
