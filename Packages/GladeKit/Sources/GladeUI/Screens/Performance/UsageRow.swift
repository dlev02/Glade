import Foundation
import GladeKit

/// One row of the apps table, with each column’s value worked out once so sorting
/// never has to deal with missing figures.
nonisolated struct UsageRow: Identifiable, Hashable, Sendable {
  let app: AppUsage
  /// Share of the whole Mac’s processor, 0–100.
  let processor: Double
  /// Share of the GPU, or -1 when it isn’t recorded, so unknowns sort last.
  let graphics: Double
  /// The front app sorts as most recent, unknowns as least.
  let lastUsed: Date
  /// Bytes a second received and sent together, 0 when it isn’t measured.
  let network: Double

  init(_ app: AppUsage, logicalCores: Int, traffic: AppTraffic? = nil) {
    self.app = app
    processor = app.cpuPercent / Double(max(logicalCores, 1))
    graphics = app.gpuPercent ?? -1
    lastUsed = app.isFrontmost ? .distantFuture : app.lastActive ?? .distantPast
    network = traffic?.total ?? 0
  }

  var id: String { app.id }
  var name: String { app.name }
  var memory: Int64 { app.memoryBytes }

  /// Quit, Force Quit and Relaunch only work on apps that aren’t part of macOS or Glade.
  var canQuit: Bool { app.kind == .app && !app.isSystem && !app.isGlade }
  var canRelaunch: Bool { canQuit && app.bundlePath != nil }

  /// Why Quit is unavailable, for a tooltip.
  var quitRefusal: String? {
    if app.isGlade { return "\(Brand.name) doesn’t quit itself." }
    if app.isSystem { return "\(app.name) is part of macOS." }
    if app.kind == .process { return "\(app.name) is a process, not an app, so it can’t be asked to quit." }
    return nil
  }
}
