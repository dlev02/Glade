import AppKit
import GladeKit
import GladeUI
import SwiftUI

/// The app itself: one shared model, the scenes from the interface package, and
/// software updates.
struct GladeApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  private let updates = AppDelegate.updates

  var body: some Scene {
    GladeScenes(model: AppDelegate.model, updater: updaterHooks)
  }

  private var updaterHooks: UpdaterHooks {
    guard updates.isAvailable else { return UpdaterHooks() }
    return UpdaterHooks(
      checkForUpdates: { updates.checkNow() },
      automaticallyChecks: Binding(get: { updates.checksAutomatically }, set: { updates.checksAutomatically = $0 })
    )
  }

  init() {
    // Started before the scenes are built, so the menu has Check for Updates… from
    // the first frame. Started later, the menu was built without it and never caught up.
    updates.start()
  }
}
