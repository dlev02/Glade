import AppKit
import Foundation
import GladeKit

/// The battery and energy tools offered to agents.
extension MCPTools {
  private static let noBatteryArguments = #"{"type":"object","properties":{},"additionalProperties":false}"#

  static let battery: [MCPTool] = [
    MCPTool(
      name: "glade_battery",
      description: "The battery right now: charge, whether it’s charging (and if plugged in but not, why), time to full or left on battery, the charger, watts flowing in or out, temperature, health (System Settings’ Maximum Capacity), cycle count, the charge limit, and plain sentences for each. A Mac without a battery says so. Cheap; call it freely.",
      schema: noBatteryArguments, readOnly: true
    ) { _ in
      JSONFiles.string(await BatteryStatus.current())
    },
    MCPTool(
      name: "glade_battery_history",
      description: "What Glade recorded while the app was open: the charge, state, power and temperature every five minutes (half-hourly after two days, up to 30 days), and battery health once a day. Use it to answer how the battery did today or how health has changed over months.",
      schema: #"{"type":"object","properties":{"days":{"type":"integer","description":"How many days of charge samples (default 1, at most 30)."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      let history = BatteryHistoryStore.load()
      let days = min(30, max(1, arguments["days"]?.int ?? 1))
      struct Report: Encodable {
        var samples: [BatteryHistory.Sample]
        var health: [BatteryHistory.HealthPoint]
        var pluggedInAt: Date?
        var unpluggedAt: Date?
      }
      return JSONFiles.string(Report(
        samples: history.samples(since: Date().addingTimeInterval(-Double(days) * 86_400)), health: history.health,
        pluggedInAt: history.pluggedInAt, unpluggedAt: history.unpluggedAt
      ))
    },
    MCPTool(
      name: "glade_energy",
      description: "Apps by the energy they used: `now` (the last two seconds), `hour`, `12h`, or `unplugged` (since the battery took over), with each app’s share and notes such as keeping the Mac awake or not used for days. Energy is what macOS bills each process for the processor and neural engine; the display, graphics chip and radios aren’t in it. Longer periods come from what Glade recorded while open. Answer “what is draining my battery” with this and glade_awake.",
      schema: #"{"type":"object","properties":{"period":{"type":"string","enum":["now","hour","12h","unplugged"]},"limit":{"type":"integer","description":"How many apps (default 15)."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      let period = arguments["period"]?.string.flatMap(EnergyPeriod.init(rawValue:)) ?? .now
      let sampler = SystemSampler()
      _ = sampler.processesNow()
      try await Task.sleep(for: .seconds(2))
      let apps = AppGrouper.group(await sampler.processes())
      let history = BatteryHistoryStore.load()
      let unplugged = BatteryReader.read().state == .onBattery ? history.unpluggedSince() : nil
      var report = EnergyReport.build(period: period, apps: apps, history: history, unpluggedAt: unplugged)
      report.apps = Array(report.apps.prefix(arguments["limit"]?.int ?? 15))
      return JSONFiles.string(report)
    },
    MCPTool(
      name: "glade_awake",
      description: "What is keeping the Mac or its screen awake: each app, simulator or tool, what it’s doing in plain words, since when, and who started a tool such as caffeinate. Requests one process holds for another (coreaudiod for whatever plays sound) are credited to the real one. Also says when sleep is turned off for the whole Mac. Never quit something keeping the Mac awake without asking: it may be a download, an export or a call.",
      schema: #"{"type":"object","properties":{"includeSystem":{"type":"boolean","description":"Include macOS’s own requests."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      var report = await AwakeReport.current()
      if arguments["includeSystem"]?.bool != true { report.holders = report.notable }
      return JSONFiles.string(report)
    },
    MCPTool(
      name: "glade_sleeps",
      description: "Recent sleeps from the power log (up to two weeks): when, how long, the charge before and after, how many times the Mac woke by itself and why in plain words (the network, Power Nap, a check-in by macOS), and what finally woke it. Reading the log takes a few seconds the first time.",
      schema: #"{"type":"object","properties":{"limit":{"type":"integer","description":"How many sleeps, newest first (default 10)."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      JSONFiles.string(Array(await SleepLog.recent().prefix(arguments["limit"]?.int ?? 10)))
    },
    MCPTool(
      name: "glade_charge_limit",
      description: "The charge limit set in System Settings › Battery › Battery Health. Glade can read it but can’t change it: macOS only takes a new limit from System Settings. With `open` true it opens that pane for the person, which brings System Settings to the front; ask first.",
      schema: #"{"type":"object","properties":{"open":{"type":"boolean","description":"Open System Settings on the charge limit."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      guard BatteryReader.hasBattery else { throw MCPFailure(message: "This Mac has no battery, so it has no charge limit.") }
      let limit = await ChargeLimitReader.current(force: true)
      let open = arguments["open"]?.bool ?? false
      if open {
        Log.info(.mcp, "Opened System Settings for the charge limit")
        _ = await MainActor.run { NSWorkspace.shared.open(ChargeLimit.settingsURL) }
      }
      struct Report: Encodable {
        var limit: ChargeLimit?
        var canChange: Bool
        var howToChange: String
        var opened: Bool
      }
      return JSONFiles.string(Report(limit: limit, canChange: ChargeLimit.canChange, howToChange: ChargeLimit.howToChange, opened: open))
    },
  ]
}
