import SwiftUI

/// The performance screens that can be drawn to an image with `glade snapshot <name>`.
/// Add an entry for each state worth checking: empty, busy, a sheet, an error.
enum PerformanceSnapshots {
  static let all: [String: (AppModel) -> AnyView] = [
    "performance": { _ in AnyView(NavigationStack { PerformanceScreen() }) },
  ]
}
