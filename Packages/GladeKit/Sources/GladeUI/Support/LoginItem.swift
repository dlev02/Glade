import Foundation
import GladeKit
import ServiceManagement

/// Opening Glade at login, through the system's own login items list. Does nothing
/// when Glade isn't running from an installed app, which has no bundle to register.
enum LoginItem {
  /// Running from an `.app`, so the setting can take effect.
  static var isAvailable: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

  static var isEnabled: Bool {
    guard isAvailable else { return false }
    let status = SMAppService.mainApp.status
    return status == .enabled || status == .requiresApproval
  }

  /// The person still has to allow it in System Settings › General › Login Items.
  static var needsApproval: Bool {
    isAvailable && SMAppService.mainApp.status == .requiresApproval
  }

  static func set(_ enabled: Bool) throws {
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
