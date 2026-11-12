import Foundation

/// Keeps the battery history while the app runs: the charge every five minutes (and
/// whenever the charger comes or goes), and every five minutes the energy each app used.
/// It has no timer of its own; the app’s sampling loop hands it readings and it decides
/// whether anything is due, so it costs nothing in between.
public actor BatteryRecorder {
  private var history: BatteryHistory
  private let url: URL?
  /// Its own sampler, so its five-minute intervals don’t disturb the live screens’.
  private let sampler = SystemSampler()
  private let ledger = EnergyLedger()
  private var lastSample: Date?
  private var lastEnergy: Date?
  private var lastState: BatteryReading.State?
  private var lastHealthPercent: Int?

  /// - Parameter url: Where the history is kept. `nil` keeps it in memory only.
  public init(url: URL? = BatteryHistoryStore.url) {
    self.url = url
    history = url.map { BatteryHistoryStore.load(from: $0) } ?? BatteryHistory()
  }

  /// The history as it stands.
  public var current: BatteryHistory { history }

  /// Takes the latest reading. Returns the history when something was added, so the
  /// caller only redraws then.
  @discardableResult
  public func record(_ reading: BatteryReading, now: Date = Date()) async -> BatteryHistory? {
    var changed = false
    let pluggedChanged = lastState.map { ($0 == .onBattery) != (reading.state == .onBattery) } ?? false
    let due = lastSample.map { now.timeIntervalSince($0) >= BatteryHistory.sampleInterval } ?? true
    if reading.hasBattery, due || pluggedChanged {
      history.add(reading, now: now)
      lastSample = now
      changed = true
      if pluggedChanged { Log.info(.system, reading.state == .onBattery ? "Unplugged at \(reading.percent ?? 0)%" : "Plugged in at \(reading.percent ?? 0)%") }
    }
    lastState = reading.state
    if let health = reading.healthPercent, health != lastHealthPercent {
      if let previous = lastHealthPercent { Log.info(.system, "Battery health changed from \(previous)% to \(health)%") }
      lastHealthPercent = health
    }

    // Energy: the first listing sets the starting point, later ones measure from it.
    if lastEnergy.map({ now.timeIntervalSince($0) >= BatteryHistory.sampleInterval }) ?? true {
      lastEnergy = now
      let processes = await sampler.processes()
      let apps = AppGrouper.group(processes)
      if let used = ledger.measure(processes: processes, apps: apps, now: now) {
        history.add(energy: used.apps, seconds: used.seconds, onBattery: reading.state == .onBattery, now: now)
        changed = true
      }
    }

    guard changed else { return nil }
    history.compact(now: now)
    if let url { BatteryHistoryStore.save(history, to: url) }
    return history
  }
}
