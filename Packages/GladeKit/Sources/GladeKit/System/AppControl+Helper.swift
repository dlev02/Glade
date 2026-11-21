import AppKit
import Foundation

/// Restarting a macOS helper that has grown far past its usual size, such as the Wi-Fi
/// menu’s WiFiAgent leaking gigabytes over a few days. Only the helpers in
/// `ProcessGuide.ceilings`, only while they’re over their ceiling, only this person’s
/// own copy and only from `/System`: all checked again here, at the moment of acting.
/// macOS starts each of them again by itself, so nothing is lost.
extension AppControl {
  public static func restartHelper(_ bundleID: String, memoryBytes: Int64) async throws -> AppActionResult {
    let id = bundleID.lowercased()
    guard let ceiling = ProcessGuide.ceilings[id] else { throw AppControlError.notRestartable(bundleID) }
    guard memoryBytes > ceiling else { throw AppControlError.notRestartable(bundleID) }
    let matches = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier?.lowercased() == id && !$0.isTerminated }
    guard let app = matches.first, let url = app.bundleURL ?? app.executableURL else { throw AppControlError.notFound(bundleID) }
    let pid = app.processIdentifier
    let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
    var owner = proc_bsdshortinfo()
    let size = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
    guard url.path.hasPrefix("/System/"), proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &owner, size) == size, owner.pbsi_uid == getuid() else {
      Log.warning(.system, "Refused to restart \(name): not this person’s copy of a macOS helper")
      throw AppControlError.notRestartable(name)
    }
    let started = Date()
    // Ask first, as Quit would; a helper without a Quit gets the polite signal.
    var exited = app.terminate() ? await waitForGone(pid, seconds: 5) : false
    if !exited {
      kill(pid, SIGTERM)
      exited = await waitForGone(pid, seconds: 5)
    }
    var reopened: pid_t?
    if exited {
      for _ in 0..<40 {
        if let fresh = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == id && $0.processIdentifier != pid }) {
          reopened = fresh.processIdentifier
          break
        }
        try? await Task.sleep(for: .milliseconds(250))
      }
    }
    let seconds = Date().timeIntervalSince(started)
    let message = !exited
      ? "\(name) didn’t stop when asked."
      : reopened != nil ? "\(name) restarted, and macOS opened it again." : "\(name) stopped; macOS opens it again when it’s needed."
    Log.info(.system, "Restart \(name) (pid \(pid), \(Format.bytes(memoryBytes))): \(exited ? "stopped" : "still running")\(reopened.map { ", back as pid \($0)" } ?? "") after \(String(format: "%.1f", seconds))s")
    return AppActionResult(
      action: .relaunch, name: name, bundleIdentifier: app.bundleIdentifier, pid: pid,
      exited: exited, relaunchedPID: reopened, seconds: seconds, message: message
    )
  }

  private static func waitForGone(_ pid: pid_t, seconds: Double) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if !(kill(pid, 0) == 0 || errno == EPERM) { return true }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return !(kill(pid, 0) == 0 || errno == EPERM)
  }
}
