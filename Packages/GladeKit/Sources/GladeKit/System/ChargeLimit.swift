import Foundation
import Synchronization

/// The charge limit set in System Settings › Battery (macOS 26.4 and later).
///
/// Glade reads it with `pmset -g battlimit`, which needs no administrator rights. It
/// can’t change it: powerd only accepts a new limit from System Settings, through a
/// private interface, so Glade opens that pane instead of pretending.
public struct ChargeLimit: Codable, Sendable, Hashable {
  /// The level macOS stops charging at. `nil` when no limit is set or it couldn’t be read.
  public var percent: Int?
  /// A limit is set. `nil` when `pmset` couldn’t be read.
  public var isOn: Bool?
  /// What `pmset -g battlimit` printed, for the technical view.
  public var raw: String?
  public var readAt: Date

  /// Where the limit is changed.
  public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension?batteryhealth")!
  /// Glade can’t set the limit itself: there is no supported way to without the
  /// System Settings app.
  public static let canChange = false
  public static let howToChange = "Change it in System Settings › Battery › Battery Health."

  /// "80%", "Off", or "Unknown".
  public var title: String {
    switch isOn {
    case true?: percent.map { "\($0)%" } ?? "On"
    case false?: "Off"
    case nil: "Unknown"
    }
  }

  /// Parses `pmset -g battlimit`. With no limit it prints "No battery level limits set";
  /// with one it prints "Battery level limits:" and the limits it holds, whose keys
  /// vary between versions, so any percentage-like number under a key naming a limit
  /// or a state of charge is taken.
  public static func parse(_ output: String, now: Date = Date()) -> ChargeLimit {
    let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return ChargeLimit(percent: nil, isOn: nil, raw: nil, readAt: now) }
    if text.lowercased().contains("no battery level limits") { return ChargeLimit(percent: nil, isOn: false, raw: text, readAt: now) }
    var best: Int?
    for line in text.split(whereSeparator: \.isNewline) {
      let lower = line.lowercased()
      guard lower.contains("soc") || lower.contains("limit") || lower.contains("level") || lower.contains("charge") else { continue }
      let digits = line.split { !$0.isNumber }.compactMap { Int($0) }.filter { (50...100).contains($0) }
      if let value = digits.last { best = min(best ?? value, value) }
    }
    return ChargeLimit(percent: best, isOn: best.map { $0 < 100 } ?? true, raw: text, readAt: now)
  }
}

/// Reads the limit, at most once every few minutes: it only changes when the person
/// changes it in System Settings.
public enum ChargeLimitReader {
  private static let cache = Mutex<ChargeLimit?>(nil)
  static let refresh: TimeInterval = 300

  public static func current(force: Bool = false, now: Date = Date()) async -> ChargeLimit? {
    guard BatteryReader.hasBattery else { return nil }
    if !force, let cached = cache.withLock({ $0 }), now.timeIntervalSince(cached.readAt) < refresh { return cached }
    do {
      let result = try await Shell.run("/usr/bin/pmset", ["-g", "battlimit"], timeout: 5, quiet: true)
      guard result.succeeded else {
        SystemIssues.warn("pmset.battlimit", "pmset -g battlimit exited \(result.status); charge limit unknown")
        return cache.withLock { $0 }
      }
      let limit = ChargeLimit.parse(result.stdout, now: now)
      let previous = cache.withLock { cache -> ChargeLimit? in
        let old = cache
        cache = limit
        return old
      }
      if previous?.isOn != limit.isOn || previous?.percent != limit.percent {
        Log.info(.system, "Charge limit: \(limit.title)")
      }
      return limit
    } catch {
      SystemIssues.warn("pmset.battlimit.run", "pmset -g battlimit couldn’t run: \(error.localizedDescription)")
      return cache.withLock { $0 }
    }
  }

  /// The last limit read, without running anything.
  public static var cached: ChargeLimit? { cache.withLock { $0 } }
}
