import SwiftUI

/// The settings screens that can be drawn to an image with `glade snapshot <name>`.
/// Add an entry for each state worth checking: empty, busy, a sheet, an error.
enum SettingsSnapshots {
  static let all: [String: (AppModel) -> AnyView] = [
    "settings": { _ in AnyView(SettingsView()) },
    "setup": { _ in AnyView(SetupView()) },
    "menubar": { _ in AnyView(MenuBarView()) },
  ]
}
