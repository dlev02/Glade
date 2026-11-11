import Foundation
import GladeKit
import SwiftUI

/// The settings screens that can be drawn to an image with `glade snapshot <name>`.
/// Add an entry for each state worth checking: empty, busy, a sheet, an error.
enum SettingsSnapshots {
  static let all: [String: (AppModel) -> AnyView] = {
    var all: [String: (AppModel) -> AnyView] = [
      "settings": { _ in AnyView(SettingsView().environment(\.screenOverrides, settingsOverrides)) },
      "settings-report": { _ in AnyView(ReportSheet()) },
      "setup": { _ in AnyView(SetupView().environment(\.screenOverrides, ScreenOverrides(setup: .nothingDone))) },
      "setup-done": { model in
        AnyView(SetupView().environment(\.screenOverrides, ScreenOverrides(setup: .allDone(providers: model.providers))))
      },
      "menubar": { model in
        AnyView(MenuBarView().environment(\.screenOverrides, ScreenOverrides(suggestions: sampleSuggestion(model))))
      },
      "menubar-calm": { _ in AnyView(MenuBarView().environment(\.screenOverrides, ScreenOverrides(suggestions: []))) },
    ]
    for tab in SettingsTab.allCases {
      all["settings-\(tab.rawValue)"] = { _ in
        AnyView(SettingsView(initialTab: tab).environment(\.screenOverrides, settingsOverrides))
      }
    }
    return all
  }()

  /// Settings as on a Mac with Glade installed, the command line tool in place and
  /// Claude Code connected.
  private static let settingsOverrides = ScreenOverrides(
    commandLine: .installed(path: NSHomeDirectory() + "/.local/bin/glade", onPath: true),
    agents: [.claude: .connected, .codex: .notConnected],
    opensAtLogin: true
  )

  /// One "quit this idle app" suggestion for the busiest real app, so the popover's
  /// suggestion row can be seen whatever this Mac is doing.
  private static func sampleSuggestion(_ model: AppModel) -> [PerformanceSuggestion] {
    guard let app = model.apps.filter({ $0.kind == .app }).max(by: { $0.memoryBytes < $1.memoryBytes }) else { return [] }
    let json: [String: Any] = [
      "id": "quitIdleApp:\(app.id)", "kind": "quitIdleApp", "appID": app.id, "appName": app.name,
      "title": "Quit \(app.name)",
      "reason": "Not used for 3 hours and holding \(Format.bytes(app.memoryBytes)) of memory.",
      "facts": "Idle 3 h · \(Format.bytes(app.memoryBytes))",
      "frees": ["memoryBytes": app.memoryBytes, "cpuPercent": 0.4],
      "confidence": "high", "actionable": true,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: json),
          let suggestion = try? JSONDecoder().decode(PerformanceSuggestion.self, from: data)
    else { return [] }
    return [suggestion]
  }
}
