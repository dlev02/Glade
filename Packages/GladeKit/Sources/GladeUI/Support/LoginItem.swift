import Foundation
import GladeKit
import ServiceManagement

/// Opening Glade at login, through the system’s own login items list. Only a copy
/// installed in an Applications folder can be registered: a development build or a
/// copy run from a disk image would leave a login item pointing at something that
/// won’t be there tomorrow.
public enum LoginItem {
  /// Installed in an Applications folder, so the setting can take effect and last.
  public static var isAvailable: Bool {
    let path = Bundle.main.bundlePath
    return path.hasSuffix(".app") && (path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/"))
  }

  /// Removes a login item registered by this copy, wherever it is running from.
  /// Used to clean up after a copy that should never have registered one.
  public static func removeRegardless() {
    guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
    do {
      try SMAppService.mainApp.unregister()
      Log.info(.app, "Removed this copy’s login item")
    } catch {
      Log.info(.app, "No login item to remove for this copy (\(error.localizedDescription))")
    }
  }

  public static var isEnabled: Bool {
    guard isAvailable else { return false }
    let status = SMAppService.mainApp.status
    return status == .enabled || status == .requiresApproval
  }

  /// The person still has to allow it in System Settings › General › Login Items.
  public static var needsApproval: Bool {
    isAvailable && SMAppService.mainApp.status == .requiresApproval
  }

  public static func set(_ enabled: Bool) throws {
    guard isAvailable else { return }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      Log.info(.app, "Open at login turned \(enabled ? "on" : "off")")
    } catch {
      Log.warning(.app, "Couldn’t turn open at login \(enabled ? "on" : "off"): \(error.localizedDescription)")
      throw error
    }
  }
}
