import AppKit
import Foundation
import GladeKit

/// Installed apps: opening a vendor’s uninstaller and showing an app in Finder. Moving
/// one to the Trash is an ordinary clean of its finding.
extension AppModel {
  /// Opens the app’s own uninstaller. The next scan lists what it leaves behind.
  public func openUninstaller(_ finding: Finding) {
    guard let path = finding.app?.uninstaller else { return }
    // Sample data never opens anything on the Mac.
    guard !isDemo else { return }
    Log.info(.app, "Opened the uninstaller for \(finding.title)")
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
  }

  /// Selects an item in Finder, where an app the system account owns can be moved to
  /// the Trash with the person’s password.
  public func showInFinder(_ path: String) {
    guard !isDemo else { return }
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
  }
}

extension AppModel {
  /// Opens Storage on one finding, as the whole-disk sheet’s Show in Storage does.
  public func revealInStorage(_ id: String) {
    section = .storage
    StorageReveal.request(id)
  }
}

/// A finding Storage should show, asked for from elsewhere in the window. Kept until
/// Storage takes it, in case Storage hasn’t been drawn yet.
@MainActor
enum StorageReveal {
  private(set) static var pending: String?

  static func request(_ id: String) {
    pending = id
    NotificationCenter.default.post(name: .gladeRevealFinding, object: nil)
  }

  static func take() -> String? {
    defer { pending = nil }
    return pending
  }
}

extension Notification.Name {
  static let gladeRevealFinding = Notification.Name("gladeRevealFinding")
}
