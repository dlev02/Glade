import AppKit
import GladeKit

/// The bookkeeping behind the Battery section, kept out of observation.
final class BatteryWork {
  var recorder: BatteryRecorder?
  /// Its own sampler, for the awake report’s occasional listing.
  let sampler = SystemSampler()
  /// How many screens are showing the Battery section.
  var watchers = 0
  var lastRead: Date?
  var lastAwake: Date?
  var busy = false
  /// Sample data is showing; live readings leave it alone.
  var frozen = false
  var wakeObserver: NSObjectProtocol?
  var loadingSleeps = false
}

/// Battery and energy: readings, history, what keeps the Mac awake, sleeps, alerts and
/// suggestions, all on the model’s own sampling loop.
extension AppModel {
  /// How often the battery is read while its section shows, and otherwise.
  static let batteryWatchedSeconds: TimeInterval = 4
  static let batteryIdleSeconds: TimeInterval = 60
  /// How often the awake report is refreshed on screen, and in the background on
  /// battery when its alert is on.
  static let awakeWatchedSeconds: TimeInterval = 8
  static let awakeIdleSeconds: TimeInterval = 300

  /// The Battery section appeared. Pair with `batteryDisappeared`.
  public func batteryAppeared() {
    batteryWork.watchers += 1
    surfaceAppeared(detail: true)
    batteryWork.lastRead = nil
    batteryWork.lastAwake = nil
    if !battery.sleepsLoaded { loadSleeps(force: false) }
  }

  public func batteryDisappeared() {
    batteryWork.watchers = max(0, batteryWork.watchers - 1)
    surfaceDisappeared(detail: true)
  }

  /// Called on every reading of the sampling loop; does work only when it’s due.
  func sampleBattery() async {
    let work = batteryWork
    guard isLive, !work.frozen, !work.busy else { return }
    let now = Date()
    let watching = work.watchers > 0
    if let last = work.lastRead, now.timeIntervalSince(last) < (watching ? Self.batteryWatchedSeconds : Self.batteryIdleSeconds) { return }
    work.busy = true
    defer { work.busy = false }
    work.lastRead = now
    if work.recorder == nil {
      work.recorder = BatteryRecorder()
      battery.history = await work.recorder?.current ?? BatteryHistory()
      observeWake()
    }

    let limit = await ChargeLimitReader.current(now: now)
    _ = await BatteryHealthReader.current(now: now)
    let reading = BatteryReader.read(limit: limit, now: now)
    if let updated = await work.recorder?.record(reading, now: now) { battery.history = updated }
    let status = BatteryStatus.make(reading: reading, limit: limit, history: battery.history, now: now)
    battery.status = status

    let awakeEvery: TimeInterval? =
      watching ? Self.awakeWatchedSeconds
      : reading.state == .onBattery && config.automation.awakeOnBatteryAlerts ? Self.awakeIdleSeconds : nil
    if let awakeEvery, work.lastAwake.map({ now.timeIntervalSince($0) >= awakeEvery }) ?? true {
      work.lastAwake = now
      battery.awake = await AwakeReport.current(
        apps: watching && !apps.isEmpty ? apps : nil, simulators: watching ? simulators : nil, sampler: work.sampler, now: now
      )
    }

    if watching, !apps.isEmpty {
      let hour = EnergyReport.build(period: .hour, apps: apps, history: battery.history, unpluggedAt: nil, now: now)
      battery.hourEnergy = hour
      battery.suggestions = PerformanceAdvisor.batterySuggestions(
        apps: apps, energy: hour, context: context ?? ActivityContext.current(apps: apps, power: snapshot?.power), config: config, now: now
      )
    }

    for alert in await monitor.ingest(battery: status, awake: battery.awake, sleeps: battery.sleeps, now: now) {
      alerts.insert(alert, at: 0)
      if alerts.count > 20 { alerts.removeLast() }
      await Notifier.post(title: alert.title, body: alert.body, kind: alert.kind.rawValue)
    }
  }

  /// Reads recent sleeps from the power log, off the main thread.
  func loadSleeps(force: Bool) {
    guard isLive, !batteryWork.frozen, !batteryWork.loadingSleeps else { return }
    batteryWork.loadingSleeps = true
    Task {
      let records = await SleepLog.recent(force: force)
      battery.sleeps = records
      battery.sleepsLoaded = true
      batteryWork.loadingSleeps = false
    }
  }

  /// After a wake the power log has a new sleep; read it when someone could use it.
  private func observeWake() {
    guard batteryWork.wakeObserver == nil else { return }
    batteryWork.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        Log.info(.system, "Woke from sleep")
        guard self.batteryWork.watchers > 0 || self.config.automation.sleepDrainAlerts else {
          self.battery.sleepsLoaded = false
          return
        }
        Task {
          // Give powerd a moment to write the wake down.
          try? await Task.sleep(for: .seconds(30))
          self.loadSleeps(force: true)
        }
      }
    }
  }

  // MARK: What the screen asks for

  /// The apps using the most energy over a period.
  public func energyReport(_ period: EnergyPeriod) -> EnergyReport {
    if let sample = battery.sampleEnergy?[period] { return sample }
    let unplugged = battery.status?.reading.state == .onBattery ? battery.history.unpluggedSince() : nil
    return EnergyReport.build(period: period, apps: apps, history: battery.history, unpluggedAt: unplugged)
  }

  /// "Battery" or "Energy" on a Mac without one.
  public var batteryTitle: String {
    (battery.status?.reading.hasBattery ?? BatteryReader.hasBattery) ? "Battery" : "Energy"
  }

  /// Opens System Settings on the battery’s health and charge limit.
  public func openChargeLimitSettings() {
    Log.info(.app, "Opened System Settings for the charge limit")
    NSWorkspace.shared.open(ChargeLimit.settingsURL)
  }

  /// What the fitting action for something keeping the Mac awake is called, or `nil`
  /// when Glade leaves it alone.
  public func actionTitle(for holder: AwakeHolder) -> String? {
    switch holder.kind {
    case .app:
      if isDemo { return "Quit" }
      return apps.contains { $0.id == holder.appID && $0.kind == .app && !$0.isSystem && !$0.isGlade } ? "Quit" : nil
    case .simulator:
      if isDemo { return "Shut Down" }
      return simulators.contains { $0.udid == holder.simulatorUDID } ? "Shut Down" : nil
    case .process, .system:
      return nil
    }
  }

  /// Quits the app or shuts down the simulator, and says what happened.
  public func perform(_ holder: AwakeHolder) async -> String {
    if isDemo { return "Sample data: nothing was changed." }
    switch holder.kind {
    case .app:
      guard let app = apps.first(where: { $0.id == holder.appID }) else { return "\(holder.name) is no longer running." }
      let message = await quit(app)
      batteryWork.lastAwake = nil
      return message
    case .simulator:
      guard let simulator = simulators.first(where: { $0.udid == holder.simulatorUDID }) else { return "That simulator is no longer running." }
      let message = await shutDown(simulator)
      batteryWork.lastAwake = nil
      return message
    case .process, .system:
      return holder.startedBy.map { "Stop it in \($0)." } ?? "\(Brand.name) leaves \(holder.name) alone."
    }
  }

  /// Quits an app from the energy table.
  public func quit(energy use: EnergyUse) async -> String {
    if isDemo { return "Sample data: nothing was changed." }
    guard let app = apps.first(where: { $0.id == use.id }) else { return "\(use.name) is no longer running." }
    return await quit(app)
  }

  /// Force quits an app from the energy table, after the person confirmed.
  public func forceQuit(energy use: EnergyUse) async -> String {
    if isDemo { return "Sample data: nothing was changed." }
    guard let app = apps.first(where: { $0.id == use.id }) else { return "\(use.name) is no longer running." }
    return await quit(app, force: true)
  }

  /// Shows fixed battery figures, for snapshots and sample data. Live readings stop.
  func loadBatterySample(_ sample: BatteryState) {
    batteryWork.frozen = true
    battery = sample
  }
}

extension AppModel {
  /// Brings what keeps the Mac awake and recent sleeps up to date before the assistant
  /// is asked, since they’re otherwise only read while the Battery section shows.
  func refreshBatteryForAssistant() async {
    guard isLive, !batteryWork.frozen else { return }
    let now = Date()
    if batteryWork.lastAwake.map({ now.timeIntervalSince($0) > 60 }) ?? true {
      batteryWork.lastAwake = now
      battery.awake = await AwakeReport.current(apps: apps.isEmpty ? nil : apps, simulators: simulators, sampler: batteryWork.sampler, now: now)
    }
    if !battery.sleepsLoaded {
      battery.sleeps = await SleepLog.recent()
      battery.sleepsLoaded = true
    }
  }

  /// The battery’s part of what the assistant is told about this Mac.
  var batteryBrief: MacDescription.Battery? {
    guard battery.status != nil || !apps.isEmpty else { return nil }
    let onBattery = battery.status?.reading.state == .onBattery
    var energy = energyReport(onBattery ? .unplugged : .hour)
    if energy.apps.isEmpty { energy = energyReport(.now) }
    return MacDescription.Battery(status: battery.status, energy: energy, awake: battery.awake, sleeps: battery.sleeps)
  }
}

