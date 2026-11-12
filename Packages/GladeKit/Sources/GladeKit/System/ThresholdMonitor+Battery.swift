import Foundation

/// What the battery alerts remember between readings.
struct BatteryAlertState: Sendable {
  var hotSince: Date?
  /// The charger session already warned about going past the limit.
  var warnedPastLimit = false
  var lastLimitOn: Bool?
  /// The sleep already warned about.
  var warnedSleep: Date?
  /// Holders already warned about, so a long night isn’t one alert an hour.
  var warnedHolders: Set<String> = []
}

/// The battery alerts: past the limit, limit turned off, hot while plugged in, health
/// below 80%, kept awake on battery, and a heavy drain while asleep. Each says what
/// happened and what to do in one sentence.
extension ThresholdMonitor {
  /// Degrees at which a plugged-in battery counts as hot, and for how long.
  static let hotCelsius = 40.0
  static let hotMinutes = 10.0
  /// Kept awake on battery for this long is worth saying.
  static let awakeMinutes = 60.0

  public func ingest(battery status: BatteryStatus, awake: AwakeReport?, sleeps: [SleepRecord], now: Date = Date()) -> [ThresholdAlert] {
    guard settings.enabled, status.reading.hasBattery else { return [] }
    let reading = status.reading
    let percent = reading.percent ?? 0
    var alerts: [ThresholdAlert] = []

    if !reading.isPluggedIn { battery.warnedPastLimit = false }
    if settings.batteryPastLimitAlerts, let limit = status.limit?.percent, reading.isPluggedIn, percent >= limit + 3,
      !battery.warnedPastLimit, mayFire(.chargedPastLimit, now: now)
    {
      battery.warnedPastLimit = true
      alerts.append(make(.chargedPastLimit, now, "Charged past your limit", "The battery is at \(percent)%, above your \(limit)% limit; macOS does this now and then to keep its gauge accurate, so check System Settings › Battery only if it keeps happening."))
    }

    if let on = status.limit?.isOn {
      if settings.chargeLimitOffAlerts, battery.lastLimitOn == true, !on, mayFire(.chargeLimitOff, now: now) {
        alerts.append(make(.chargeLimitOff, now, "Charge limit turned off", "Your Mac will now charge to 100%; turn the limit back on in System Settings › Battery if you didn’t mean to."))
      }
      battery.lastLimitOn = on
    }

    if let temperature = reading.temperatureCelsius, reading.isPluggedIn, temperature >= Self.hotCelsius {
      let since = battery.hotSince ?? now
      battery.hotSince = since
      if settings.batteryHotAlerts, now.timeIntervalSince(since) >= Self.hotMinutes * 60, mayFire(.batteryHot, now: now) {
        alerts.append(make(.batteryHot, now, "Battery is hot while charging", "It has been \(BatteryFormat.temperature(temperature)) for \(Int(Self.hotMinutes)) minutes, so let your Mac cool down or unplug it for a while, as charging a hot battery wears it faster."))
      }
    } else {
      battery.hotSince = nil
    }

    // Said once; repeating it wouldn’t tell anyone anything new.
    if settings.batteryHealthAlerts, let health = reading.healthPercent, health < 80,
      lastFired[.batteryHealth].map({ now.timeIntervalSince($0) > 180 * 86_400 }) ?? true
    {
      alerts.append(make(.batteryHealth, now, "Battery health is below 80%", "It now holds \(health)% of its charge when new; System Settings › Battery shows whether it needs a service."))
    }

    if reading.state == .onBattery, let awake {
      for holder in awake.notable {
        guard let seconds = holder.seconds(now: now), seconds >= Self.awakeMinutes * 60, !battery.warnedHolders.contains(holder.id) else { continue }
        guard settings.awakeOnBatteryAlerts, mayFire(.awakeOnBattery, now: now) else { break }
        battery.warnedHolders.insert(holder.id)
        let what = holder.startedBy.map { "\(holder.name), started by \($0)," } ?? holder.name
        let action: String =
          switch holder.kind {
          case .simulator: "shut it down if you’re not using it"
          case .process: holder.startedBy.map { "stop it in \($0) if you don’t need it" } ?? "stop it if you don’t need it"
          default: "quit it if you’re not using it"
          }
        alerts.append(make(.awakeOnBattery, now, "Kept awake on battery", "\(what) has kept your Mac awake for \(Durations.phrase(seconds)) on battery; \(action)."))
        break
      }
    } else {
      battery.warnedHolders = []
    }

    if settings.sleepDrainAlerts, let last = sleeps.first, last.onBattery, last.start != battery.warnedSleep,
      now.timeIntervalSince(last.end) < 1800, last.seconds >= 3600,
      let drain = last.drain, let rate = last.drainPerHour, drain >= 6, rate >= 2, mayFire(.sleepDrain, now: now)
    {
      battery.warnedSleep = last.start
      let wakes = last.wakes.isEmpty ? "" : ", waking \(last.wakes.count == 1 ? "once" : "\(last.wakes.count) times")\(last.wakeCounts.first.map { " mostly for \($0.reason)" } ?? "")"
      alerts.append(make(.sleepDrain, now, "Battery drained while asleep", "It lost \(drain)% over \(Durations.phrase(last.seconds)) asleep\(wakes); \(Brand.name)’s Battery section shows what woke it."))
    }

    if !alerts.isEmpty {
      for alert in alerts {
        lastFired[alert.kind] = now
        Log.info(.automation, "Alert: \(alert.kind.rawValue): \(alert.body)")
      }
      save()
    }
    return alerts
  }
}
