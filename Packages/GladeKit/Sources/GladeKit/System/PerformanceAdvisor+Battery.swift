import Foundation

/// Suggestions about the battery: an app left alone that is still drawing power, and
/// one that has kept the Mac awake long after anyone used it. The same apps are off
/// limits as for memory: the one in front, anything playing or recording sound,
/// anything doing real work, macOS’s own apps and anything kept running on purpose.
extension PerformanceAdvisor {
  /// Average power over the last hour that’s worth mentioning for an idle app.
  public static let idleDrainWatts = 0.3
  /// Unused for this long before power use counts against an app.
  public static let idleDrainMinutes = 60.0
  /// Keeping the Mac awake this long, unused, makes it look forgotten.
  public static let forgottenAwakeMinutes = 60.0

  /// - Parameter energy: The last hour’s energy, so one busy moment doesn’t count.
  ///   Without it the live figure is used.
  public static func batterySuggestions(
    apps: [AppUsage], energy: EnergyReport?, context: ActivityContext, config: GladeConfig = ConfigStore.load(), now: Date = Date()
  ) -> [PerformanceSuggestion] {
    let keep = Set(config.keepRunning.map { $0.lowercased() })
    let frontID = context.frontmostApp?.id
    let hourly = Dictionary((energy?.apps ?? []).map { ($0.id, $0.watts) }, uniquingKeysWith: { first, _ in first })
    var result: [PerformanceSuggestion] = []

    for app in apps where app.kind == .app && !app.isSystem && !app.isGlade && !app.isFrontmost && app.id != frontID {
      if keep.contains(app.id.lowercased()) || keep.contains(app.name.lowercased())
        || app.bundleIdentifier.map({ keep.contains($0.lowercased()) }) == true { continue }
      if app.isPlayingAudio || app.isCapturingAudio || app.cpuPercent >= workingCPUPercent { continue }
      guard let last = app.lastActive else { continue }
      let unused = now.timeIntervalSince(last)
      let frees = PerformanceSuggestion.Frees(memoryBytes: app.memoryBytes, cpuPercent: app.cpuPercent, gpuPercent: app.gpuPercent)

      if app.preventingSleep != nil {
        guard let since = app.preventingSleepSince, unused >= forgottenAwakeMinutes * 60,
          now.timeIntervalSince(since) >= forgottenAwakeMinutes * 60, app.cpuPercent < quietCPUPercent
        else { continue }
        let held = now.timeIntervalSince(since)
        result.append(PerformanceSuggestion(
          id: "\(PerformanceSuggestion.Kind.forgottenAwakeHolder.rawValue):\(app.id)", kind: .forgottenAwakeHolder, appID: app.id, appName: app.name,
          pid: nil, title: "Quit \(app.name)",
          reason: "\(app.name) has kept your Mac awake for \(Durations.phrase(held)) and hasn’t been used for \(Durations.phrase(unused)).",
          frees: frees, confidence: .low, actionable: true,
          facts: "Awake \(shortDuration(held)) · Idle \(shortDuration(unused))",
          caveat: "Check it isn’t finishing something", idleSeconds: unused
        ))
        continue
      }

      guard unused >= idleDrainMinutes * 60, let watts = hourly[app.id] ?? app.energyWatts, watts >= idleDrainWatts else { continue }
      let strong = unused >= 3 * 3600 && watts >= 0.5
      result.append(PerformanceSuggestion(
        id: "\(PerformanceSuggestion.Kind.idleEnergyDrain.rawValue):\(app.id)", kind: .idleEnergyDrain, appID: app.id, appName: app.name,
        pid: nil, title: "Quit \(app.name)",
        reason: "\(app.name) hasn’t been used for \(Durations.phrase(unused)) but is still using \(BatteryFormat.watts(watts)) in the background.",
        frees: frees, confidence: strong ? .medium : .low, actionable: true,
        facts: "Idle \(shortDuration(unused)) · \(BatteryFormat.watts(watts))", idleSeconds: unused
      ))
    }
    return result.sorted { (hourly[$0.appID] ?? 0) > (hourly[$1.appID] ?? 0) }
  }
}
