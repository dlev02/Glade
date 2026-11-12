import AppKit
import ArgumentParser
import Foundation
import GladeKit

/// The battery: charge, health, power, temperature, the charge limit and estimates.
struct Battery: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show the battery’s charge, health, power, temperature, charge limit and estimates.",
    subcommands: [BatteryNow.self, BatteryHistoryCommand.self, ChargeLimitCommand.self],
    defaultSubcommand: BatteryNow.self
  )
}

struct BatteryNow: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "now",
    abstract: "Show the battery right now (the default)."
  )

  @OptionGroup var output: OutputOptions

  func run() async throws {
    let status = await BatteryStatus.current()
    emit(status, json: output.json) {
      for line in BatteryText.lines(status) { print(line) }
    }
  }
}

struct BatteryHistoryCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "history",
    abstract: "Show the charge, power and health Glade has recorded, day by day.",
    discussion: "The app records this while it runs: the charge every five minutes and battery health once a day. It stays on this Mac."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "How many days to cover (up to 30 for the charge; health goes back further).")
  var days = 7

  struct Day: Encodable {
    var date: String
    var lowest: Int
    var highest: Int
    var hoursOnBattery: Double
    var hoursCharging: Double
    var averageDrawWatts: Double?
    var hottest: Double?
  }

  struct Report: Encodable {
    var days: Int
    var samples: [BatteryHistory.Sample]
    var byDay: [Day]
    var health: [BatteryHistory.HealthPoint]
    var note: String?
  }

  func run() async throws {
    let history = BatteryHistoryStore.load()
    let since = Date().addingTimeInterval(-Double(max(1, days)) * 86_400)
    let samples = history.samples(since: since)
    let calendar = Calendar.current
    var byDay: [Day] = []
    let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }
    for (day, list) in grouped.sorted(by: { $0.key < $1.key }) {
      let sorted = list.sorted { $0.date < $1.date }
      var battery = 0.0, charging = 0.0
      for (index, sample) in sorted.enumerated() {
        let next = index + 1 < sorted.count ? sorted[index + 1].date : min(Date(), sample.date.addingTimeInterval(BatteryHistory.sampleInterval))
        let span = min(next.timeIntervalSince(sample.date), BatteryHistory.sampleInterval * 7)
        if sample.state == .onBattery { battery += span }
        if sample.state == .charging { charging += span }
      }
      let draws = sorted.filter { $0.state == .onBattery }.compactMap { $0.batteryWatts.map { -$0 } }.filter { $0 > 0 }
      byDay.append(Day(
        date: day.formatted(.iso8601.year().month().day()), lowest: sorted.map(\.percent).min() ?? 0, highest: sorted.map(\.percent).max() ?? 0,
        hoursOnBattery: (battery / 360).rounded() / 10, hoursCharging: (charging / 360).rounded() / 10,
        averageDrawWatts: draws.isEmpty ? nil : (draws.reduce(0, +) / Double(draws.count) * 10).rounded() / 10,
        hottest: sorted.compactMap(\.temperature).max()
      ))
    }
    let note = samples.isEmpty ? "Nothing recorded yet: \(Brand.name) records the battery while the app is open." : nil
    let report = Report(days: days, samples: samples, byDay: byDay, health: history.health, note: note)
    emit(report, json: output.json) {
      if let note {
        print(note)
        return
      }
      print("DAY         CHARGE     ON BATTERY  CHARGING  AVG DRAW  HOTTEST")
      for day in byDay {
        let charge = "\(day.lowest)–\(day.highest)%"
        print("\(day.date)  \(charge.padding(toLength: 9, withPad: " ", startingAt: 0))  \(String(format: "%.1f h", day.hoursOnBattery).leftPadded(10))  \(String(format: "%.1f h", day.hoursCharging).leftPadded(8))  \((day.averageDrawWatts.map { BatteryFormat.watts($0) } ?? "—").leftPadded(8))  \((day.hottest.map(BatteryFormat.temperature) ?? "—").leftPadded(7))")
      }
      if let first = history.health.first, let last = history.health.last {
        print("")
        print("Health: \(first.percent)% on \(first.date.formatted(date: .abbreviated, time: .omitted)), \(last.percent)% on \(last.date.formatted(date: .abbreviated, time: .omitted)) (\(history.health.count) readings)")
      }
    }
  }
}

struct ChargeLimitCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "limit",
    abstract: "Show the charge limit, or open System Settings to change it.",
    discussion: "Glade can read the limit but not set it: macOS only takes a new limit from System Settings › Battery. --open opens that pane."
  )

  @OptionGroup var output: OutputOptions

  @Flag(name: .long, help: "Open System Settings › Battery, where the limit is changed.")
  var open = false

  struct Report: Encodable {
    var limit: ChargeLimit?
    var canChange: Bool
    var howToChange: String
    var settings: String
    var opened: Bool
  }

  func run() async throws {
    guard BatteryReader.hasBattery else {
      throw ValidationError("This Mac has no battery, so it has no charge limit.")
    }
    let limit = await ChargeLimitReader.current(force: true)
    if open {
      Log.info(.cli, "Opened System Settings for the charge limit")
      NSWorkspace.shared.open(ChargeLimit.settingsURL)
    }
    let report = Report(
      limit: limit, canChange: ChargeLimit.canChange, howToChange: ChargeLimit.howToChange,
      settings: ChargeLimit.settingsURL.absoluteString, opened: open
    )
    emit(report, json: output.json) {
      switch limit?.isOn {
      case true?: print("Charge limit: \(limit?.title ?? "on"). macOS stops charging there.")
      case false?: print("Charge limit: off. The battery charges to 100%.")
      case nil: print("Charge limit: couldn’t be read.")
      }
      print(open ? "Opened System Settings › Battery." : "\(ChargeLimit.howToChange) Run `\(Brand.cli) battery limit --open` to go there.")
    }
  }
}

/// Apps by the energy they used.
struct Energy: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List apps by the energy they used: now, in the last hour, 12 hours, or since unplugged.",
    discussion: "Energy is what macOS bills each process for the processor and neural engine. The display, graphics chip and radios aren’t included. Longer periods come from what the app recorded while it was open."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "now, hour, 12h or unplugged.")
  var period: EnergyPeriod = .now

  @Option(name: .long, help: "How many apps to list.")
  var limit = 15

  func run() async throws {
    let sampler = SystemSampler()
    // Two listings a couple of seconds apart, for a steady "now".
    _ = sampler.processesNow()
    try await Task.sleep(for: .seconds(2))
    let apps = AppGrouper.group(await sampler.processes())
    let history = BatteryHistoryStore.load()
    let unplugged = BatteryReader.read().state == .onBattery ? history.unpluggedSince() : nil
    var report = EnergyReport.build(period: period, apps: apps, history: history, unpluggedAt: unplugged)
    report.apps = Array(report.apps.prefix(max(0, limit)))
    emit(report, json: output.json) {
      if let note = report.note { print(note) }
      guard !report.apps.isEmpty else { return }
      let header = period == .now ? "POWER" : "AVERAGE"
      print("\(header.leftPadded(8))  \("ENERGY".leftPadded(9))  \("SHARE".leftPadded(5))  NAME")
      for use in report.apps {
        let energy = period == .now ? "—" : BatteryFormat.energy(use.joules)
        let notes = use.notes.isEmpty ? "" : "  [\(use.notes.joined(separator: ", "))]"
        print("\(BatteryFormat.watts(use.watts).leftPadded(8))  \(energy.leftPadded(9))  \(Format.percent(use.share).leftPadded(5))  \(use.name)\(use.isSystem ? " (macOS)" : "")\(notes)")
      }
      print("\nAll measured: \(BatteryFormat.watts(report.totalWatts)) on average. \(report.measures)")
    }
  }
}

extension EnergyPeriod: ExpressibleByArgument {}

/// What is keeping the Mac awake.
struct Awake: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show what is keeping the Mac (or its screen) awake, since when, and why."
  )

  @OptionGroup var output: OutputOptions

  @Flag(name: .long, help: "Include macOS’s own requests.")
  var all = false

  func run() async throws {
    var report = await AwakeReport.current()
    if !all { report.holders = report.holders.filter { $0.kind != .system } }
    emit(report, json: output.json) {
      print(report.summary)
      if report.sleepDisabled {
        print("  An app or a `pmset disablesleep` command turned sleep off; it stays off until it’s turned back on.")
      }
      let now = Date()
      for holder in report.holders {
        let held = holder.seconds(now: now).map { " for \(BatteryFormat.duration($0))" } ?? ""
        print("• \(holder.name)\(holder.kind == .system ? " (macOS)" : ""): \(holder.sentence)\(held)")
        var detail = holder.rawNames.joined(separator: "; ")
        if let heldBy = holder.heldBy { detail += " (held by \(heldBy))" }
        print("  \(holder.rawTypes.joined(separator: ", ")): \(detail)")
      }
    }
  }
}

/// Recent sleeps, with drain and wakes.
struct Sleeps: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List recent sleeps: how long, the charge before and after, and what woke the Mac."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "How many sleeps to list.")
  var limit = 10

  struct Report: Encodable {
    var days: Int
    var sleeps: [SleepRecord]
    var note: String?
  }

  func run() async throws {
    let sleeps = Array(await SleepLog.recent(force: true).prefix(max(0, limit)))
    let settings = SleepSettings.read()
    var note: String?
    if sleeps.isEmpty {
      note = settings.sleepDisabled
        ? "No sleeps in the last \(SleepLog.days) days: sleep is turned off for this whole Mac."
        : "No sleeps in the last \(SleepLog.days) days."
    }
    emit(Report(days: SleepLog.days, sleeps: sleeps, note: note), json: output.json) {
      if let note { print(note) }
      for sleep in sleeps {
        let when = sleep.start.formatted(date: .abbreviated, time: .shortened)
        let charge = [sleep.chargeBefore, sleep.chargeAfter].compactMap { $0.map { "\($0)%" } }.joined(separator: " → ")
        let drain = sleep.drain.map { $0 > 0 ? ", lost \($0)%" : $0 < 0 ? ", gained \(-$0)%" : "" } ?? ""
        print("• \(when): \(BatteryFormat.duration(sleep.seconds)) asleep (\(sleep.reason.lowercased()), \(sleep.onBattery ? "on battery" : "plugged in")), \(charge)\(drain)")
        print("  \(sleep.wakeSummary)\(sleep.wokeBy.map { " Woken by \($0)." } ?? " Restarted.")")
        for count in sleep.wakeCounts.prefix(4) { print("    \(count.count)× \(count.reason)") }
      }
    }
  }
}

/// The battery in plain lines, shared by `battery` and `status`.
enum BatteryText {
  static func lines(_ status: BatteryStatus) -> [String] {
    let reading = status.reading
    guard reading.hasBattery else {
      var line = "Power   \(status.sentence)"
      if let adapter = reading.adapter { line += "; \(adapter.name)\(adapter.watts.map { ", \($0) W" } ?? "")" }
      return [line]
    }
    var lines = ["Battery \(reading.percent.map { "\($0)%" } ?? "?"): \(status.sentence)"]
    if let adapter = reading.adapter {
      var line = "Charger \(adapter.name)\(adapter.watts.map { ", rated \($0) W" } ?? "")"
      if let delivering = reading.adapterWatts { line += ", delivering \(BatteryFormat.watts(delivering))" }
      lines.append(line)
    }
    var power: [String] = []
    if let system = reading.systemWatts { power.append("Mac using \(BatteryFormat.watts(system))") }
    if let battery = reading.batteryWatts, abs(battery) >= 0.05 {
      power.append(battery > 0 ? "battery taking in \(BatteryFormat.watts(battery))" : "battery giving \(BatteryFormat.watts(battery))")
    }
    if let volts = reading.voltage { power.append(String(format: "%.2f V", volts)) }
    if let amps = reading.amperage { power.append("\(amps) mA") }
    if !power.isEmpty { lines.append("Power   \(power.joined(separator: ", "))") }
    var health = "Health  \(reading.healthPercent.map { "\($0)%" } ?? "?") (\(reading.healthTitle))"
    if let cycles = reading.cycleCount { health += ", \(cycles) cycles\(reading.designCycleCount.map { " of \($0) designed" } ?? "")" }
    if let capacity = reading.capacitymAh, let design = reading.designCapacitymAh { health += "; holds \(capacity) of \(design) mAh" }
    if let raw = reading.rawMaxCapacitymAh { health += " (gauge \(raw) mAh)" }
    lines.append(health)
    if let temperature = reading.temperatureCelsius { lines.append("Temp    \(BatteryFormat.temperature(temperature))") }
    switch status.limit?.isOn {
    case true?: lines.append("Limit   \(status.limit?.title ?? "on"). \(ChargeLimit.howToChange)")
    case false?: lines.append("Limit   Off: charges to 100%. \(ChargeLimit.howToChange)")
    case nil: lines.append("Limit   Unknown")
    }
    let estimates = status.estimates
    var times: [String] = []
    if let minutes = estimates.minutesToTarget, let target = estimates.target { times.append("\(target)% in \(BatteryFormat.minutes(minutes))") }
    if let minutes = estimates.minutesToFull, reading.state == .charging { times.append("full in \(BatteryFormat.minutes(minutes))") }
    if let minutes = estimates.minutesLeft { times.append("\(BatteryFormat.timeLeft(minutes)) left\(estimates.averageDrawWatts.map { " at \(BatteryFormat.watts($0))" } ?? "")") }
    if let seconds = estimates.secondsOnCharger { times.append("on the charger for \(BatteryFormat.duration(seconds))") }
    if let seconds = estimates.secondsHeldFull, seconds >= 600 { times.append("held full for \(BatteryFormat.duration(seconds))") }
    if !times.isEmpty { lines.append("Times   \(times.joined(separator: "; "))") }
    return lines
  }
}
