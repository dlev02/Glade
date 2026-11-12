import Foundation

/// The battery as one value for the window, the command line and agents: the reading,
/// the limit, the estimates and the sentences that say what they mean.
public struct BatteryStatus: Codable, Sendable, Hashable {
  public var reading: BatteryReading
  public var limit: ChargeLimit?
  public var estimates: BatteryEstimates
  /// "Charging, full in 48 min", "On battery, about 5 hours left".
  public var sentence: String
  /// "Holds 84% of its charge when new, after 913 cycles."
  public var healthSentence: String?
  /// Glade can’t change the limit itself.
  public var canChangeLimit: Bool
  public var limitSettings: String

  public static func make(reading: BatteryReading, limit: ChargeLimit?, history: BatteryHistory?, now: Date = Date()) -> BatteryStatus {
    let estimates = BatteryEstimates.make(reading: reading, limit: limit, history: history, now: now)
    return BatteryStatus(
      reading: reading, limit: limit, estimates: estimates,
      sentence: sentence(reading, limit: limit, estimates: estimates),
      healthSentence: healthSentence(reading), canChangeLimit: ChargeLimit.canChange,
      limitSettings: ChargeLimit.settingsURL.absoluteString
    )
  }

  /// Reads everything now. Runs `pmset` at most every few minutes for the limit.
  public static func current(history: BatteryHistory? = nil, now: Date = Date()) async -> BatteryStatus {
    let limit = await ChargeLimitReader.current(now: now)
    _ = await BatteryHealthReader.current(now: now)
    return make(reading: BatteryReader.read(limit: limit, now: now), limit: limit, history: history ?? BatteryHistoryStore.load(), now: now)
  }

  static func sentence(_ reading: BatteryReading, limit: ChargeLimit?, estimates: BatteryEstimates) -> String {
    switch reading.state {
    case .noBattery:
      return "No battery: this Mac runs on mains power"
    case .charging:
      if let target = limit?.percent, let percent = reading.percent, percent < target {
        return estimates.minutesToTarget.map { "Charging to \(target)%, there in \(BatteryFormat.minutes($0))" } ?? "Charging to \(target)%"
      }
      return estimates.minutesToFull.map { "Charging, full in \(BatteryFormat.minutes($0))" } ?? "Charging"
    case .onBattery:
      return estimates.minutesLeft.map { "On battery, \(BatteryFormat.timeLeft($0)) left" } ?? "On battery"
    case .notCharging:
      return reading.notChargingReason ?? "Plugged in, not charging"
    case .charged:
      return "Fully charged"
    }
  }

  static func healthSentence(_ reading: BatteryReading) -> String? {
    guard let health = reading.healthPercent else { return nil }
    var text = "Holds \(health)% of its charge when new"
    if let cycles = reading.cycleCount { text += ", after \(cycles.formatted()) cycles" }
    return text + "."
  }
}
