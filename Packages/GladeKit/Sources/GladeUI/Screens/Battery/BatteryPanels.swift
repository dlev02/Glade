import GladeKit
import SwiftUI

/// Health, Power right now and Temperature side by side, in the style of Performance’s
/// panels. Simple shows words and percentages; Technical adds the figures behind them.
struct BatteryPanels: View {
  var status: BatteryStatus?
  var history: BatteryHistory
  var thermal: ThermalState?
  var detail: BatterySettings.Detail
  var columns: Int
  var now: Date

  var body: some View {
    if columns >= 3 {
      HStack(alignment: .top, spacing: Metrics.l) {
        health
        power
        temperature
      }
      .fixedSize(horizontal: false, vertical: true)
    } else {
      VStack(spacing: Metrics.l) {
        HStack(alignment: .top, spacing: Metrics.l) {
          health
          power
        }
        .fixedSize(horizontal: false, vertical: true)
        temperature
      }
    }
  }

  private var reading: BatteryReading? { status?.reading }
  private var technical: Bool { detail == .technical }

  /// The last six hours of samples, for the panels’ small charts.
  private var recent: [BatteryHistory.Sample] { history.samples(since: now.addingTimeInterval(-6 * 3600)) }

  // MARK: Health

  private var health: some View {
    let percent = reading?.healthPercent
    let worn = (percent ?? 100) < 80 || (reading?.condition.map { $0.lowercased() != "normal" } ?? false)
    return LivePanel(
      title: "Health", symbol: "heart",
      figure: percent.map { "\($0)%" } ?? "—",
      unit: percent == nil ? nil : "of new",
      status: reading == nil ? .measuring
        : PanelStatus(text: reading?.healthTitle ?? "", symbol: nil, color: worn ? Palette.warning : Palette.good, prominent: worn),
      history: history.health.map { HistoryChart.Point(date: $0.date, value: Double($0.percent)) },
      color: worn ? Palette.warning : Palette.good,
      summary: status?.healthSentence ?? "Measuring"
    ) {
      PanelFact("Charge cycles", reading?.cycleCount.map { cycles in
        technical ? reading?.designCycleCount.map { "\(cycles.formatted()) of \($0.formatted())" } ?? cycles.formatted() : cycles.formatted()
      } ?? "—")
      if technical {
        PanelFact("Holds", capacity(reading?.capacitymAh, of: reading?.designCapacitymAh))
        PanelFact("Gauge reads", reading?.rawMaxCapacitymAh.map { "\($0.formatted()) mAh" } ?? "—")
      } else {
        PanelFact("Condition", reading?.condition ?? (percent == nil ? "—" : "Normal"))
      }
    }
  }

  private func capacity(_ value: Int?, of design: Int?) -> String {
    guard let value else { return "—" }
    return design.map { "\(value.formatted()) of \($0.formatted()) mAh" } ?? "\(value.formatted()) mAh"
  }

  // MARK: Power

  /// Light, Moderate or Heavy, against what the charger (or a typical charger) gives.
  private var load: (word: String, fraction: Double)? {
    guard let watts = reading?.systemWatts else { return nil }
    let scale = Double(max(reading?.adapter?.watts ?? 60, 30))
    let fraction = min(1, watts / scale)
    let word = fraction < 0.25 ? "Light" : fraction < 0.6 ? "Moderate" : "Heavy"
    return (word, fraction)
  }

  private var power: some View {
    let flow = reading?.batteryWatts
    let scale = Double(max(reading?.adapter?.watts ?? 60, 30))
    return LivePanel(
      title: "Power right now", symbol: "bolt",
      figure: technical ? (reading?.systemWatts.map(BatteryFormat.watts) ?? "—") : (load?.word ?? "—"),
      unit: technical && reading?.systemWatts != nil ? "in use" : nil,
      status: reading == nil ? .measuring : PanelStatus(text: stateWord, symbol: nil, color: .secondary, prominent: false),
      history: recent.compactMap { sample in
        sample.systemWatts.map { HistoryChart.Point(date: sample.date, value: min(100, $0 / scale * 100)) }
      },
      color: Palette.load(load?.fraction ?? 0),
      summary: [load?.word, reading?.systemWatts.map { "using \(BatteryFormat.watts($0))" }, stateWord].compactMap { $0 }.joined(separator: ", ")
    ) {
      if let adapter = reading?.adapter {
        PanelFact("Charger", technical ? "\(adapter.name)\(adapter.watts.map { ", \($0) W" } ?? "")" : adapter.name)
      } else {
        PanelFact("Charger", reading?.hasBattery == false ? "—" : "Not connected")
      }
      if technical {
        PanelFact("Battery", flow.map { abs($0) < 0.05 ? "Resting" : $0 > 0 ? "Taking in \(BatteryFormat.watts($0))" : "Giving \(BatteryFormat.watts($0))" } ?? "—")
        PanelFact("Voltage", reading?.voltage.map { String(format: "%.2f V", $0) } ?? "—")
        PanelFact("Current", reading?.amperage.map { "\($0.formatted()) mA" } ?? "—")
      } else {
        PanelFact(timeLabel, timeValue)
      }
    }
  }

  private var stateWord: String {
    switch reading?.state {
    case .charging: "Charging"
    case .onBattery: "On battery"
    case .notCharging: "Not charging"
    case .charged: "Charged"
    case .noBattery, nil: "Plugged in"
    }
  }

  private var timeLabel: String {
    switch reading?.state {
    case .onBattery: "Time left"
    case .charging: status?.estimates.minutesToTarget != nil && status?.limit?.percent != nil
      ? "\(status?.estimates.target ?? 80)% in" : "Full in"
    default: "On the charger"
    }
  }

  private var timeValue: String {
    let estimates = status?.estimates
    switch reading?.state {
    case .onBattery: return estimates?.minutesLeft.map { BatteryFormat.minutes($0) } ?? "—"
    case .charging:
      if status?.limit?.percent != nil, let minutes = estimates?.minutesToTarget { return BatteryFormat.minutes(minutes) }
      return estimates?.minutesToFull.map { BatteryFormat.minutes($0) } ?? "—"
    default: return estimates?.secondsOnCharger.map { PerformanceFormat.uptime($0) } ?? "—"
    }
  }

  // MARK: Temperature

  private var temperature: some View {
    let celsius = reading?.temperatureCelsius
    let word = celsius.map { $0 < 35 ? "Normal" : $0 < 40 ? "Warm" : "Hot" }
    let color: Color = celsius.map { $0 < 35 ? Palette.good : $0 < 40 ? Palette.warning : Palette.critical } ?? .secondary
    let hottest = history.samples(since: Calendar.current.startOfDay(for: now)).compactMap(\.temperature).max()
    return LivePanel(
      title: "Temperature", symbol: "thermometer.medium",
      figure: celsius.map(BatteryFormat.temperature) ?? "—",
      unit: nil,
      status: word.map { PanelStatus(text: $0, symbol: nil, color: color, prominent: $0 != "Normal") } ?? .measuring,
      // 20 °C at the bottom, 50 °C at the top.
      history: recent.compactMap { sample in
        sample.temperature.map { HistoryChart.Point(date: sample.date, value: min(100, max(0, ($0 - 20) / 30 * 100))) }
      },
      color: color,
      summary: [celsius.map(BatteryFormat.temperature), word].compactMap { $0 }.joined(separator: ", ")
    ) {
      PanelFact("Hottest today", hottest.map(BatteryFormat.temperature) ?? "—")
      PanelFact("The Mac", thermal.map(Self.thermalWord) ?? "—")
    }
  }

  private static func thermalWord(_ state: ThermalState) -> String {
    switch state {
    case .nominal: "Cool"
    case .fair: "Warm"
    case .serious: "Hot"
    case .critical: "Very hot"
    }
  }
}
