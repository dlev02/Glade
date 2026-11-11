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
  ]

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
