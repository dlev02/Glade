import Foundation

/// Which stretch of time the energy table covers.
public enum EnergyPeriod: String, Codable, Sendable, CaseIterable, Identifiable {
  case now
  case hour
  case halfDay = "12h"
  case unplugged

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .now: "Now"
    case .hour: "Last Hour"
    case .halfDay: "12 Hours"
    case .unplugged: "Since Unplugged"
    }
  }
}

/// One app’s share of the energy used over a period.
public struct EnergyUse: Codable, Sendable, Identifiable, Hashable {
  public var id: String
  public var name: String
  public var bundlePath: String?
  public var kind: AppUsage.Kind
  /// Joules over the period; for "now", what the last few seconds would add up to.
  public var joules: Double
  /// Average power over the period.
  public var watts: Double
  /// Share of everything measured, 0–1.
  public var share: Double
  /// Short notes for the row: "Keeping your Mac awake", "Not used for 3 days".
  public var notes: [String]
  public var isSystem: Bool
  public var isGlade: Bool
  public var isRunning: Bool
}

/// The apps using the most energy over a period.
public struct EnergyReport: Codable, Sendable {
  public var period: EnergyPeriod
  public var since: Date?
  /// Seconds the figures cover. Less than the period when Glade wasn’t running for all of it.
  public var seconds: Double
  /// Average power of everything measured.
  public var totalWatts: Double
  public var apps: [EnergyUse]
  /// Said when the figures are thin or missing: "Glade records this while it’s open."
  public var note: String?
  /// What the numbers measure, for agents and the technical view.
  public var measures = "Processor and neural engine energy macOS billed each process (rusage ri_energy_nj); the graphics chip, display and radios aren’t included."

  /// - Parameters:
  ///   - apps: The live listing, for "now" and for each row’s notes.
  ///   - unpluggedAt: When the battery took over, for `.unplugged`; `nil` on the charger.
  public static func build(
    period: EnergyPeriod, apps: [AppUsage], history: BatteryHistory?, unpluggedAt: Date?, now: Date = Date()
  ) -> EnergyReport {
    let live = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var since: Date?
    var rows: [(id: String, name: String, path: String?, joules: Double, watts: Double)] = []
    var seconds = 0.0
    var note: String?

    switch period {
    case .now:
      for app in apps {
        guard let watts = app.energyWatts, watts > 0.0005 else { continue }
        rows.append((app.id, app.name, app.bundlePath, watts, watts))
      }
      seconds = 1
      if rows.isEmpty { note = "Measuring…" }
    case .hour, .halfDay, .unplugged:
      let start: Date? =
        switch period {
        case .hour: now.addingTimeInterval(-3600)
        case .halfDay: now.addingTimeInterval(-12 * 3600)
        default: unpluggedAt
        }
      since = start
      if let start, let history {
        let used = history.energy(since: start)
        seconds = used.seconds
        for app in used.apps where app.id != BatteryHistory.otherID {
          rows.append((app.id, app.name, app.bundlePath, app.joules, seconds > 0 ? app.joules / seconds : 0))
        }
      }
      if start == nil {
        note = "Your Mac is on the charger."
      } else if rows.isEmpty {
        note = "\(Brand.name) records this while it’s open, every five minutes."
      } else if let start, seconds < now.timeIntervalSince(start) * 0.8 {
        note = "Covers the \(Durations.phrase(seconds)) \(Brand.name) was open."
      }
    }

    let total = rows.reduce(0) { $0 + $1.watts }
    let uses = rows.sorted { $0.watts > $1.watts }.map { row -> EnergyUse in
      let app = live[row.id]
      return EnergyUse(
        id: row.id, name: row.name, bundlePath: row.path ?? app?.bundlePath, kind: app?.kind ?? (row.path == nil ? .process : .app),
        joules: row.joules, watts: row.watts, share: total > 0 ? row.watts / total : 0,
        notes: notes(for: app, now: now), isSystem: app?.isSystem ?? false, isGlade: app?.isGlade ?? false,
        isRunning: app != nil
      )
    }
    return EnergyReport(period: period, since: since, seconds: seconds, totalWatts: total, apps: uses, note: note)
  }

  /// What’s worth knowing about an app beside its energy, most telling first.
  static func notes(for app: AppUsage?, now: Date) -> [String] {
    guard let app else { return ["Not running now"] }
    var notes: [String] = []
    if app.preventingSleep != nil { notes.append("Keeping your Mac awake") }
    if app.isPlayingAudio { notes.append("Playing sound") }
    if let last = app.lastActive, !app.isFrontmost, now.timeIntervalSince(last) >= 86_400 {
      notes.append("Not used for \(Durations.phrase(now.timeIntervalSince(last)))")
    } else if app.kind == .app, !app.isFrontmost, !app.isSystem, app.activationPolicy != .regular || app.windowCount == 0 {
      notes.append("In the background")
    }
    if app.isFrontmost { notes.append("In use") }
    return notes
  }
}
