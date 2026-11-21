import AppKit
import GladeKit
import GladeUI

/// Launch and quit housekeeping. Glade lives in the menu bar, so closing its window
/// leaves it running.
final class AppDelegate: NSObject, NSApplicationDelegate {
  static let model = AppModel()
  static let updates = UpdateController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // A second copy would double every alert and fight over the same settings. A copy
    // showing sample data (`-demo YES`, for checking screens) does neither, so it may
    // run beside the real one.
    let isSample = UserDefaults.standard.bool(forKey: "demo")
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
      .filter { $0 != .current }
    if !isSample, let existing = others.first {
      Log.info(.app, "Another copy is already running (pid \(existing.processIdentifier)); bringing it forward and quitting")
      existing.activate()
      NSApp.terminate(nil)
      return
    }
    Self.model.start()
    if isSample { SampleWindowShot.listen() }
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

/// A sample copy draws its own window to a file when `glade drive shot` asks, because
/// with Stage Manager a background window is only a thumbnail to screen capture. Only
/// sample copies listen.
enum SampleWindowShot {
  static let request = Notification.Name("io.github.dlev02.glade.drive.shot")

  static func listen() {
    DistributedNotificationCenter.default().addObserver(forName: request, object: nil, queue: .main) { note in
      guard let path = note.object as? String, path.hasPrefix("/") else { return }
      MainActor.assumeIsolated { draw(to: path) }
    }
  }

  @MainActor
  static func draw(to path: String) {
    guard let window = NSApp.windows.filter({ $0.isVisible && $0.contentView != nil })
      .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
      let view = window.contentView?.superview ?? window.contentView,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
  }
}
