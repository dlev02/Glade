import Foundation
import GladeKit

/// Words for showing an installed app.
extension Finding {
  var isApp: Bool { category == .installedApps }

  /// The app comes with its own uninstaller, which Glade opens instead.
  var hasOwnUninstaller: Bool { blockers.contains { $0.kind == .ownUninstaller } }

  /// Only Finder can move it to the Trash, because it needs the person’s password.
  var needsFinder: Bool { isApp && !hasOwnUninstaller && blockers.contains { $0.kind == .needsAdmin } }

  var isAppOpen: Bool { isApp && blockers.contains { $0.kind == .appRunning } }

  /// "Opened 8 months ago", "Open now", or nothing when macOS never recorded it.
  var openedText: String? {
    if isAppOpen { return "Open now" }
    return lastUsed.map { "Opened \(Format.age($0))" }
  }

  /// How much a list puts it ahead of others: big apps that haven’t been opened in a
  /// long time first. A year unused weighs twelve times a month; one used today, a
  /// quarter. Apps with no record count as a month.
  var appPriority: Double {
    let days = Double(idleDays() ?? 30)
    return Double(bytes) * min(max(days / 30, 0.25), 12)
  }
}
