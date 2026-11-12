import Foundation

/// Describes the state of this Mac in plain text for an assistant: what’s using
/// memory and the processors, what the person is doing, and what the last scan
/// found. App and process names only; never file contents.
public enum MacDescription {
  /// The battery’s part of the description: names, numbers and plain reasons only.
  public struct Battery: Sendable {
    public var status: BatteryStatus?
    public var energy: EnergyReport?
    public var awake: AwakeReport?
    public var sleeps: [SleepRecord]

    public init(status: BatteryStatus?, energy: EnergyReport?, awake: AwakeReport?, sleeps: [SleepRecord]) {
      self.status = status
      self.energy = energy
      self.awake = awake
      self.sleeps = sleeps
    }
  }

  public static func build(
    snapshot: SystemSnapshot?, apps: [AppUsage], context: ActivityContext?,
    suggestions: [PerformanceSuggestion], scan: ScanResult?, plan: CleanPlan?, battery: Battery? = nil
  ) -> String {
    var lines: [String] = []
    if let snapshot {
      lines.append("SYSTEM")
      lines.append("Processor: \(Int(snapshot.cpu.totalPercent))% of \(snapshot.cpu.logicalCores) cores, load \(snapshot.cpu.loadAverage.map { String(format: "%.1f", $0) }.joined(separator: " "))")
      lines.append("Memory: \(Format.bytes(snapshot.memory.usedBytes)) used of \(Format.bytes(snapshot.memory.totalBytes)), pressure \(snapshot.memory.pressure.rawValue), swap \(Format.bytes(snapshot.memory.swapUsedBytes))")
      if let gpu = snapshot.gpu?.utilizationPercent { lines.append("Graphics: \(Int(gpu))%") }
      lines.append("Disk: \(Format.bytes(snapshot.disk.availableBytes)) free of \(Format.bytes(snapshot.disk.totalBytes))")
      lines.append("Power: \(snapshot.power.onBattery ? "on battery" : "plugged in")\(snapshot.power.lowPowerMode ? ", low power mode" : ""); thermal \(snapshot.thermal.rawValue)")
    }
    if let context {
      lines.append("")
      lines.append("WHAT THE PERSON IS DOING")
      if let front = context.frontmostApp { lines.append("In front: \(front.name)\(front.isFullScreen ? " (full screen)" : "")") }
      lines.append("Last input: \(Int(context.secondsSinceInput)) seconds ago")
      if context.isGaming { lines.append("Gaming: \(context.gamingReason ?? "yes")") }
      for signal in context.signals.prefix(8) { lines.append("Active: \(signal.appName) — \(signal.detail)") }
    }
    if !apps.isEmpty {
      lines.append("")
      lines.append("APPS BY MEMORY (name | memory | processor | graphics | notes)")
      for app in apps.sorted(by: { $0.memoryBytes > $1.memoryBytes }).prefix(25) {
        var notes: [String] = []
        if app.isFrontmost { notes.append("in front") }
        if app.isPlayingAudio { notes.append("playing audio") }
        if app.isCapturingAudio { notes.append("using the microphone") }
        if let reason = app.preventingSleep { notes.append("keeping the Mac awake: \(reason)") }
        if app.isSystem { notes.append("part of macOS") }
        if let last = app.lastActive, !app.isFrontmost { notes.append("last used \(Format.age(last))") }
        if app.windowCount == 0, app.kind == .app { notes.append("no windows") }
        lines.append("\(app.name) | \(Format.bytes(app.memoryBytes)) | \(Int(app.cpuPercent))% | \(app.gpuPercent.map { "\(Int($0))%" } ?? "-") | \(notes.joined(separator: ", "))")
      }
    }
    if let battery { lines += describe(battery) }
    if !suggestions.isEmpty {
      lines.append("")
      lines.append("WHAT GLADE'S RULES SUGGEST")
      for suggestion in suggestions.prefix(8) { lines.append("\(suggestion.title): \(suggestion.reason)") }
    }
    if let scan {
      lines.append("")
      lines.append("STORAGE (scanned \(Format.age(scan.finished)))")
      // Installed apps aren't described: they're the person's alone to choose.
      let findings = scan.findings.filter(\.category.countsAsReclaimable)
      lines.append("Reclaimable: \(Format.bytes(scan.totalBytes)) in \(findings.count) findings")
      var totals: [StorageCategory: Int64] = [:]
      for finding in findings where finding.within == nil { totals[finding.category, default: 0] += finding.bytes }
      for (category, bytes) in totals.sorted(by: { $0.value > $1.value }).prefix(12) {
        lines.append("\(category.title): \(Format.bytes(bytes))")
      }
      for level in CleanLevel.allCases {
        let plan = Planner.plan(scan: scan, level: level)
        let trash = plan.selectedBytes - plan.immediateBytes
        lines.append("A \(level.title) clean would free \(Format.bytes(plan.immediateBytes))" + (trash > 0 ? " and move \(Format.bytes(trash)) to the Trash (freed only when the Trash is emptied)" : ""))
      }
      if let plan { lines.append("Currently selected: \(Format.bytes(plan.selectedBytes)) at \(plan.level.title)") }
    }
    return lines.joined(separator: "\n")
  }

  /// BATTERY and ENERGY: charge, health, limit, what keeps the Mac awake, recent sleeps,
  /// and the apps using the most energy.
  static func describe(_ battery: Battery, now: Date = Date()) -> [String] {
    var lines: [String] = []
    if let status = battery.status {
      let reading = status.reading
      lines.append("")
      lines.append("BATTERY")
      if reading.hasBattery {
        lines.append("Charge: \(reading.percent.map { "\($0)%" } ?? "unknown"); \(status.sentence)")
        var power: [String] = []
        if let adapter = reading.adapter { power.append("charger \(adapter.name)\(adapter.watts.map { " \($0) W" } ?? "")") }
        if let system = reading.systemWatts { power.append("the Mac is using \(BatteryFormat.watts(system))") }
        if let watts = reading.batteryWatts, abs(watts) >= 0.05 { power.append("battery \(watts > 0 ? "taking in" : "giving") \(BatteryFormat.watts(watts))") }
        if !power.isEmpty { lines.append("Power: \(power.joined(separator: ", "))") }
        var health = "Health: \(reading.healthPercent.map { "\($0)% of its capacity when new" } ?? "unknown") (\(reading.healthTitle))"
        if let cycles = reading.cycleCount { health += ", \(cycles) charge cycles\(reading.designCycleCount.map { " of \($0) designed" } ?? "")" }
        lines.append(health)
        if let temperature = reading.temperatureCelsius { lines.append("Temperature: \(BatteryFormat.temperature(temperature))") }
        lines.append("Charge limit: \(status.limit?.title ?? "unknown") (set in System Settings › Battery › Battery Health; Glade can’t change it)")
        if let minutes = status.estimates.minutesLeft { lines.append("Left on battery at the recent rate: \(BatteryFormat.timeLeft(minutes))") }
        if let seconds = status.estimates.secondsOnCharger { lines.append("On the charger for \(Durations.phrase(seconds))") }
      } else {
        lines.append("This Mac has no battery.")
      }
      if reading.lowPowerMode { lines.append("Low Power Mode is on.") }
    }
    if let awake = battery.awake {
      if awake.sleepDisabled { lines.append("Sleep is turned off for the whole Mac (pmset disablesleep), so it never sleeps by itself.") }
      if awake.notable.isEmpty {
        lines.append("Keeping the Mac awake: nothing")
      } else {
        for holder in awake.notable.prefix(8) {
          let held = holder.seconds(now: now).map { " for \(Durations.phrase($0))" } ?? ""
          lines.append("Keeping the Mac awake: \(holder.name) (\(holder.kind.rawValue)) — \(holder.sentence)\(held)")
        }
      }
    }
    for sleep in battery.sleeps.prefix(3) {
      let drain = sleep.drain.map { $0 >= 0 ? ", lost \($0)%" : ", gained \(-$0)%" } ?? ""
      lines.append("Slept \(Format.age(sleep.start)) for \(Durations.phrase(sleep.seconds)) \(sleep.onBattery ? "on battery" : "plugged in")\(drain). \(sleep.wakeSummary)")
    }
    if let energy = battery.energy, !energy.apps.isEmpty {
      lines.append("")
      let period = energy.period == .now ? "right now" : energy.period == .unplugged ? "since unplugged" : energy.period == .hour ? "in the last hour" : "in the last 12 hours"
      lines.append("ENERGY \(period.uppercased()) (name | average power | share | notes)")
      lines.append("Processor energy macOS billed each app; the screen, graphics chip and radios aren’t included. All apps together: \(BatteryFormat.watts(energy.totalWatts)).")
      for use in energy.apps.prefix(12) {
        var notes = use.notes
        if use.isSystem { notes.append("part of macOS") }
        lines.append("\(use.name) | \(BatteryFormat.watts(use.watts)) | \(Format.percent(use.share)) | \(notes.joined(separator: ", "))")
      }
    }
    return lines
  }

  /// A one-paragraph summary of recent activity, for the storage assistant.
  public static func activity(context: ActivityContext?, apps: [AppUsage]) -> String? {
    guard let context else { return nil }
    var parts: [String] = []
    if let front = context.frontmostApp { parts.append("\(front.name) is in front") }
    let busy = context.signals.filter { $0.kind == .highCPU }.map(\.appName)
    if !busy.isEmpty { parts.append("busy right now: \(Array(Set(busy)).sorted().joined(separator: ", "))") }
    let open = apps.filter { $0.kind == .app && !$0.isSystem }.map(\.name)
    if !open.isEmpty { parts.append("open apps: \(open.prefix(20).joined(separator: ", "))") }
    return parts.isEmpty ? nil : parts.joined(separator: "; ")
  }
}
