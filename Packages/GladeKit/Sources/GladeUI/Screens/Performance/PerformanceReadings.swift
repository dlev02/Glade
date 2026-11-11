import GladeKit

/// The live figures the Performance screen draws. Normally read straight from the
/// model; snapshots can swap in a variation (no data yet, memory under pressure)
/// without touching the model.
struct PerformanceReadings {
  var snapshot: SystemSnapshot?
  var history: [SystemSnapshot]
  var apps: [AppUsage]
  var suggestions: [PerformanceSuggestion]

  init(snapshot: SystemSnapshot?, history: [SystemSnapshot], apps: [AppUsage], suggestions: [PerformanceSuggestion]) {
    self.snapshot = snapshot
    self.history = history
    self.apps = apps
    self.suggestions = suggestions
  }

  init(model: AppModel) {
    self.init(snapshot: model.snapshot, history: model.history, apps: model.apps, suggestions: model.suggestions)
  }

  /// Logical cores, used to turn per-app figures (a share of one core) into a share
  /// of the whole Mac.
  var logicalCores: Int { max(snapshot?.cpu.logicalCores ?? 1, 1) }
}
