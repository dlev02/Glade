import Foundation

/// Times worked out from the battery, its limit and its recent history.
public struct BatteryEstimates: Codable, Sendable, Hashable {
  /// macOS’s own estimate to a full charge.
  public var minutesToFull: Int?
  /// To the charge limit, or to 80% when there isn’t one, while charging below it.
  public var minutesToTarget: Int?
  public var target: Int?
  /// Left on battery at the recent rate of use.
  public var minutesLeft: Int?
  /// The rate that estimate uses: the average over the last half hour on battery.
  public var averageDrawWatts: Double?
  /// How long it has been on the charger this time.
  public var secondsOnCharger: Double?
  /// How long of that it has sat full (or at its limit).
  public var secondsHeldFull: Double?

  public static func make(reading: BatteryReading, limit: ChargeLimit?, history: BatteryHistory?, now: Date = Date()) -> BatteryEstimates {
    var estimates = BatteryEstimates()
    guard reading.hasBattery, let percent = reading.percent else { return estimates }
    estimates.minutesToFull = reading.minutesToFull

    let target = limit?.percent ?? 80
    estimates.target = target
    let capacity = Double(reading.rawMaxCapacitymAh ?? reading.capacitymAh ?? 0)
    let volts = reading.voltage ?? 0
    if reading.state == .charging, percent < target, let watts = reading.batteryWatts, watts > 0.5, capacity > 0, volts > 0 {
      let needed = Double(target - percent) / 100 * capacity * volts / 1000
      estimates.minutesToTarget = max(1, Int((needed / watts * 60).rounded()))
    }

    if reading.state == .onBattery {
      var draws = (history?.samples(since: now.addingTimeInterval(-1800)) ?? [])
        .filter { $0.state == .onBattery }
        .compactMap { $0.batteryWatts.map { -$0 } }
      if let current = reading.batteryWatts { draws.append(-current) }
      let positive = draws.filter { $0 > 0.2 }
      if !positive.isEmpty, let left = reading.currentCapacitymAh, volts > 0 {
        let draw = positive.reduce(0, +) / Double(positive.count)
        estimates.averageDrawWatts = draw
        let hours = Double(left) * volts / 1000 / draw
        estimates.minutesLeft = Int((hours * 60).rounded())
      } else {
        estimates.minutesLeft = reading.minutesToEmpty
      }
    }

    if reading.isPluggedIn, let since = history?.pluggedInSince(now: now) {
      estimates.secondsOnCharger = now.timeIntervalSince(since)
      let full = limit?.percent.map { $0 - 1 } ?? 99
      estimates.secondsHeldFull = history?.secondsAtOrAbove(full, since: since, now: now)
    }
    return estimates
  }
}
