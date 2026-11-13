import AppKit
import GladeKit
import GladeUI

/// Launch and quit housekeeping. Glade lives in the menu bar, so closing its window
/// leaves it running.
final class AppDelegate: NSObject, NSApplicationDelegate {
  static let model = AppModel()
  static let updates = UpdateController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // A second copy would double every alert and fight over the same settings.
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
      .filter { $0 != .current }
    if let existing = others.first {
      Log.info(.app, "Another copy is already running (pid \(existing.processIdentifier)); bringing it forward and quitting")
      existing.activate()
      NSApp.terminate(nil)
      return
    }
    Self.model.start()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// Writes the last few minutes of data used before quitting.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    Task { @MainActor in
      await Self.model.flushNetwork()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    ActivityLog.shared.flush()
    Log.info(.app, "\(Brand.name) quit")
    Log.flush()
  }
}
