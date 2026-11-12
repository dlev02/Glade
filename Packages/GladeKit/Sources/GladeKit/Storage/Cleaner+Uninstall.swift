import AppKit
import Foundation

/// Uninstalling an app: the app to the Trash, then each of its data folders, all
/// checked again now. Nothing here is deleted outright, so `glade undo` and Put Back
/// bring everything back.
extension Cleaner {
  /// Moves an app finding’s bundle and data to the Trash.
  /// - Returns: What happened, and the data folders left where they are with the reason.
  static func uninstall(
    _ finding: Finding, bundleID: String, protection: Protection, running: RunningApps, dryRun: Bool
  ) async -> (RemovalOutcome, [String: String]) {
    if let held = heldBack(finding, running: running) { return (held, [:]) }
    guard finding.category == .installedApps, let bundle = finding.paths.first.map(Protection.clean) else {
      return (.skipped(reason: "Not an app."), [:])
    }
    let name = finding.app?.name ?? finding.title

    // The app itself, by the uninstall rules, never the general ones.
    let verdict = protection.verdict(forUninstalling: bundle)
    guard verdict.isAllowed else { return (refuse(finding, bundle, verdict), [:]) }
    // Still the same app: a different one put in its place isn’t what the person chose.
    let current = InstalledApps.infoPlist(of: bundle)?["CFBundleIdentifier"] as? String
    guard let current, current.caseInsensitiveCompare(bundleID) == .orderedSame else {
      Log.error(.safety, "Refused to uninstall \(Redactor.tilde(bundle)): it is no longer \(bundleID)")
      return (.skipped(reason: "It’s no longer the same app. Scan again."), [:])
    }
    // Running right now, by identifier or from inside the bundle.
    if let open = Self.runningNow(bundle: bundle, bundleID: bundleID, running: running) {
      Log.info(.clean, "Kept \(bundleID): \(open) is open")
      return (.skipped(reason: "\(open) is open. Quit it first."), [:])
    }

    // Each data folder on its own: one that fails the check stays, the rest go.
    var targets: [String] = []
    var left: [String: String] = [:]
    for path in finding.paths.dropFirst() {
      var info = stat()
      guard lstat(path, &info) == 0 else { continue }
      let check = protection.verdict(forRemoving: path)
      guard check.isAllowed else {
        Log.warning(.safety, "Left \(Redactor.tilde(path)) in place for \(finding.ruleID): \(check.explanation)")
        left[path] = check.explanation
        continue
      }
      if let app = InUse.liveAppLock(for: path, home: protection.home) {
        left[path] = "\(app) is open."
        continue
      }
      if let program = InUse.runningExecutable(inside: path, executables: running.executablePaths) {
        left[path] = "\(program) is running from here."
        continue
      }
      targets.append(path)
    }
    if dryRun { return (.wouldRemove, left) }

    // The app first. If it can’t go, its data stays too, so the app isn’t left
    // without its settings.
    var locations: [String: String] = [:]
    do {
      var resulting: NSURL?
      try FileManager.default.trashItem(at: URL(fileURLWithPath: bundle), resultingItemURL: &resulting)
      locations[bundle] = resulting?.path ?? ""
    } catch {
      Log.warning(.clean, "Couldn’t move \(name) to the Trash: \(reason(error))")
      if Self.isPermission(error) {
        return (.failed(reason: "macOS needs your password to remove \(name). Select it in Finder and choose Move to Trash."), [:])
      }
      return (.failed(reason: reason(error)), [:])
    }
    for path in targets {
      do {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
        locations[path] = resulting?.path ?? ""
      } catch {
        Log.warning(.clean, "Couldn’t move \(Redactor.tilde(path)) to the Trash: \(reason(error))")
        left[path] = isPermission(error) ? "macOS wouldn’t let Glade move it." : reason(error)
      }
    }
    return (.trashed(locations: locations), left)
  }

  /// The running app that holds this bundle, asked of macOS now rather than taken
  /// from when the clean started.
  static func runningNow(bundle: String, bundleID: String, running: RunningApps) -> String? {
    for app in NSWorkspace.shared.runningApplications {
      let id = app.bundleIdentifier?.lowercased()
      let path = app.bundleURL.map { Protection.clean($0.path) }
      if id == bundleID.lowercased() || path == bundle || path?.hasPrefix(bundle + "/") == true {
        return app.localizedName ?? bundleID
      }
    }
    return InUse.runningExecutable(inside: bundle, executables: running.executablePaths)
  }

  static func isPermission(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError { return true }
    if nsError.domain == NSPOSIXErrorDomain, [Int(EACCES), Int(EPERM)].contains(nsError.code) { return true }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isPermission(underlying) }
    return false
  }
}
