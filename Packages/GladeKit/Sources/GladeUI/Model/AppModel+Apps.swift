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
