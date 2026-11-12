import Foundation

/// Everything keeping the Mac awake right now, and the settings that stop it sleeping.
public struct AwakeReport: Codable, Sendable {
  public var date: Date
  public var holders: [AwakeHolder]
  /// Sleep is turned off for the whole Mac (`pmset disablesleep`), usually by an app
  /// that keeps Macs awake.
  public var sleepDisabled: Bool
  /// The Mac is set never to sleep by itself on the power source it’s using.
  public var neverSleepsOnThisPower: Bool
  public var onBattery: Bool

  /// The holders a person would act on: everything not part of macOS.
  public var notable: [AwakeHolder] { holders.filter { $0.kind != .system } }

  /// One plain sentence: "Nothing is keeping your Mac awake." or "2 things are…".
  public var summary: String {
    if sleepDisabled { return "Sleep is turned off for this whole Mac." }
    let count = notable.count
    switch count {
    case 0: return neverSleepsOnThisPower ? "Your Mac is set never to sleep on the charger." : "Nothing is keeping your Mac awake."
    case 1: return "\(notable[0].name) is keeping your Mac awake."
    default: return "\(count) things are keeping your Mac awake."
    }
  }

  /// Reads the requests and the settings now.
  /// - Parameters:
  ///   - apps: A listing already taken, so the live screens don’t take another. A fresh
  ///     one is taken when `nil`.
  ///   - simulators: The booted simulators, for requests made inside one.
  public static func current(
    apps known: [AppUsage]? = nil, simulators knownSimulators: [SimulatorUsage]? = nil,
    sampler: SystemSampler = SystemSampler(), now: Date = Date()
  ) async -> AwakeReport {
    let assertions = SleepAssertions.current()
    var processes: [ProcessSample] = []
    var apps = known ?? []
    if known == nil {
      processes = await sampler.processes()
      apps = AppGrouper.group(processes)
    } else {
      // The processes themselves are only needed to say who started a command-line tool.
      let covered = Set(apps.flatMap(\.pids))
      if assertions.contains(where: { $0.processName == "caffeinate" || !covered.contains($0.ownerPID) }) {
        processes = sampler.processesNow()
      }
    }
    var simulators = knownSimulators ?? []
    if knownSimulators == nil, apps.contains(where: { $0.name.localizedCaseInsensitiveContains("simulator") }) {
      simulators = await sampler.simulatorBreakdown(processes: processes.isEmpty ? nil : processes).devices
    }
    let battery = BatteryReader.read()
    return build(
      assertions: assertions, processes: processes, apps: apps, simulators: simulators,
      settings: SleepSettings.read(), onBattery: battery.state == .onBattery, now: now
    )
  }

  public static func build(
    assertions: [SleepAssertion], processes: [ProcessSample], apps: [AppUsage], simulators: [SimulatorUsage],
    settings: SleepSettings, onBattery: Bool, now: Date = Date()
  ) -> AwakeReport {
    let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    var appByPID: [Int32: AppUsage] = [:]
    for app in apps { for pid in app.pids { appByPID[pid] = app } }
    var simulatorByPID: [Int32: SimulatorUsage] = [:]
    for simulator in simulators { for pid in simulator.pids { simulatorByPID[pid] = simulator } }

    var rows: [String: AwakeHolder] = [:]
    var order: [String] = []
    for assertion in assertions {
      let pid = assertion.ownerPID
      let process = byPID[pid]
      let processName = process?.name ?? assertion.processName
      var holder: AwakeHolder
      let reason = AwakeReasons.describe(assertion)
      let heldBy = assertion.onBehalfOfPID != nil ? assertion.processName : nil
      if let simulator = simulatorByPID[pid] {
        holder = AwakeHolder(
          id: "simulator:\(simulator.udid)", kind: .simulator, name: simulator.name, appID: nil, bundlePath: nil,
          simulatorUDID: simulator.udid, pid: pid, holdsDisplay: false, since: nil, reason: reason, startedBy: nil,
          heldBy: heldBy, rawNames: [], rawTypes: [], count: 0, timeoutSeconds: nil
        )
      } else if processName.lowercased() == "caffeinate" || (appByPID[pid]?.kind == .process && !(appByPID[pid]?.isSystem ?? true)) {
        let row = appByPID[pid]
        holder = AwakeHolder(
          id: "process:\(processName)-\(pid)", kind: .process, name: row?.name ?? processName, appID: row?.id, bundlePath: nil,
          simulatorUDID: nil, pid: pid, holdsDisplay: false, since: nil, reason: reason,
          startedBy: starter(of: pid, byPID: byPID, appByPID: appByPID), heldBy: heldBy,
          rawNames: [], rawTypes: [], count: 0, timeoutSeconds: nil
        )
      } else if let app = appByPID[pid] {
        let system = app.isSystem || app.kind == .process
        holder = AwakeHolder(
          id: app.id, kind: system ? .system : .app, name: app.name, appID: app.id, bundlePath: app.bundlePath,
          simulatorUDID: nil, pid: pid, holdsDisplay: false, since: nil, reason: reason, startedBy: nil, heldBy: heldBy,
          rawNames: [], rawTypes: [], count: 0, timeoutSeconds: nil
        )
      } else {
        // Gone already, or belongs to another user.
        let system = SystemApps.isSystem(path: process?.executablePath, bundleID: nil, name: processName) || process?.isCurrentUser == false || process == nil
        holder = AwakeHolder(
          id: "process:\(processName)", kind: system ? .system : .process, name: processName, appID: nil, bundlePath: nil,
          simulatorUDID: nil, pid: pid, holdsDisplay: false, since: nil, reason: reason, startedBy: nil, heldBy: heldBy,
          rawNames: [], rawTypes: [], count: 0, timeoutSeconds: nil
        )
      }
      if var existing = rows[holder.id] {
        existing.count += 1
        existing.holdsDisplay = existing.holdsDisplay || assertion.holdsDisplay
        if let start = assertion.since { existing.since = min(existing.since ?? start, start) }
        if !existing.rawNames.contains(assertion.name) { existing.rawNames.append(assertion.name) }
        if !existing.rawTypes.contains(assertion.type) { existing.rawTypes.append(assertion.type) }
        if let timeout = assertion.timeoutSeconds { existing.timeoutSeconds = max(existing.timeoutSeconds ?? 0, timeout) }
        // The most telling reason wins over the generic ones.
        if AwakeReasons.isGeneric(existing.reason) && !AwakeReasons.isGeneric(reason) { existing.reason = reason }
        rows[holder.id] = existing
      } else {
        holder.count = 1
        holder.holdsDisplay = assertion.holdsDisplay
        holder.since = assertion.since
        holder.rawNames = [assertion.name]
        holder.rawTypes = [assertion.type]
        holder.timeoutSeconds = assertion.timeoutSeconds
        rows[holder.id] = holder
        order.append(holder.id)
      }
    }
    let holders = order.compactMap { rows[$0] }.sorted { lhs, rhs in
      if (lhs.kind == .system) != (rhs.kind == .system) { return rhs.kind == .system }
      return (lhs.since ?? now) < (rhs.since ?? now)
    }
    return AwakeReport(
      date: now, holders: holders, sleepDisabled: settings.sleepDisabled,
      neverSleepsOnThisPower: onBattery ? settings.batterySleepMinutes == 0 : settings.chargerSleepMinutes == 0,
      onBattery: onBattery
    )
  }

  /// The app or tool that started a process, skipping the shells in between: Terminal
  /// for `caffeinate` typed there, `claude` for one Claude Code started.
  static func starter(of pid: Int32, byPID: [Int32: ProcessSample], appByPID: [Int32: AppUsage]) -> String? {
    var cursor = byPID[pid]?.parentPID ?? 0
    var steps = 0
    while cursor > 1, steps < 16, let parent = byPID[cursor] {
      if !AppGrouper.shells.contains(parent.name.lowercased()) {
        return appByPID[cursor]?.name ?? parent.name
      }
      cursor = parent.parentPID
      steps += 1
    }
    return nil
  }
}
