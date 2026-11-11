import GladeKit
import SwiftUI

/// The performance screens that can be drawn to an image with `glade snapshot <name>`.
/// Draw `performance` at `--width 940 --height 600` (or `window --section performance`
/// at that size) to check the minimum window.
enum PerformanceSnapshots {
  static let all: [String: (AppModel) -> AnyView] = [
    "performance": { _ in AnyView(NavigationStack { PerformanceScreen() }) },
    "performance-everything": { _ in AnyView(NavigationStack { PerformanceScreen(filter: .everything) }) },
    "performance-selected": { _ in
      AnyView(NavigationStack {
        PerformanceScreen(preselect: { model in
          model.apps.filter { $0.kind == .app && !$0.isSystem }.max { $0.memoryBytes < $1.memoryBytes }?.id
        })
      })
    },
    "performance-pressure": { _ in AnyView(NavigationStack { PerformanceScreen(readings: underPressure) }) },
    "performance-empty": { _ in
      AnyView(NavigationStack {
        PerformanceScreen(readings: { _ in PerformanceReadings(snapshot: nil, history: [], apps: [], suggestions: []) })
      })
    },
    // The shared suggestion row with a caveat, in each place it appears.
    "performance-suggestions": { _ in
      AnyView(NavigationStack {
        PerformanceScreen(readings: { model in
          var readings = PerformanceReadings(model: model)
          readings.suggestions = sampleSuggestions(model)
          return readings
        })
      })
    },
    "popover-suggestion": { model in
      AnyView(MenuBarView().environment(\.screenOverrides, ScreenOverrides(suggestions: sampleSuggestions(model))))
    },
  ]

  /// An idle simulator with a doubt about it, and an idle app, so the suggestion row
  /// can be seen with and without a caveat whatever this Mac is doing.
  private static func sampleSuggestions(_ model: AppModel) -> [PerformanceSuggestion] {
    var entries: [[String: Any]] = [[
      "id": "shutDownIdleSimulator:simulator:sample", "kind": "shutDownIdleSimulator", "appID": "simulator:sample",
      "appName": "iPad Pro 13-inch (M5)", "title": "Shut down iPad Pro 13-inch (M5)",
      "reason": "iPad Pro 13-inch (M5) (iOS 27.2) has been idle since it started 31 hours ago and is using 10.3 GB. Bitrig is open and may be showing it; Glade can’t tell which simulator Bitrig shows.",
      "frees": ["memoryBytes": 10_300_000_000, "cpuPercent": 0.2], "confidence": "low", "actionable": true,
      "simulatorUDID": "sample", "facts": "Idle 31 h · 10.3 GB", "caveat": "May be in use by Bitrig",
    ]]
    if let app = model.apps.filter({ $0.kind == .app && !$0.isSystem }).max(by: { $0.memoryBytes < $1.memoryBytes }) {
      entries.append([
        "id": "quitIdleApp:\(app.id)", "kind": "quitIdleApp", "appID": app.id, "appName": app.name,
        "title": "Quit \(app.name)",
        "reason": "\(app.name) is using \(Format.bytes(app.memoryBytes)) and hasn’t been used for 3 hours.",
        "frees": ["memoryBytes": app.memoryBytes, "cpuPercent": 0.4], "confidence": "high", "actionable": true,
        "facts": "Idle 3 h · \(Format.bytes(app.memoryBytes))",
      ])
    }
    // The engine's initialiser isn't public, so build them the way they arrive from disk.
    guard let data = try? JSONSerialization.data(withJSONObject: entries) else { return [] }
    return (try? JSONDecoder().decode([PerformanceSuggestion].self, from: data)) ?? []
  }

  /// The live readings with memory nearly full, compressing hard and swapping, and
  /// climbing over the last two minutes.
  private static func underPressure(_ model: AppModel) -> PerformanceReadings {
    var readings = PerformanceReadings(model: model)
    func squeeze(_ snapshot: SystemSnapshot, _ progress: Double) -> SystemSnapshot {
      var reading = snapshot
      let total = reading.memory.totalBytes
      let used = Int64(Double(total) * (0.78 + 0.19 * progress))
      reading.memory.usedBytes = used
      reading.memory.compressedBytes = Int64(Double(total) * 0.28 * progress)
      reading.memory.wiredBytes = Int64(Double(total) * 0.16)
      reading.memory.appBytes = max(0, used - reading.memory.compressedBytes - reading.memory.wiredBytes)
      reading.memory.cachedFilesBytes = Int64(Double(total) * 0.02)
      reading.memory.swapUsedBytes = Int64(6_400_000_000 * progress)
      reading.memory.pressure = progress > 0.8 ? .critical : progress > 0.4 ? .warning : .normal
      return reading
    }
    let count = max(readings.history.count - 1, 1)
    readings.history = readings.history.enumerated().map { squeeze($1, Double($0) / Double(count)) }
    readings.snapshot = readings.snapshot.map { squeeze($0, 1) }
    return readings
  }
}
