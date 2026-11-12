import GladeKit
import SwiftUI

/// The top of the Battery section: the charge in large type with one sentence saying
/// what it’s doing, the charge over time, and the charge limit.
struct ChargeCard: View {
  @Environment(AppModel.self) private var model
  var status: BatteryStatus?
  var history: BatteryHistory
  var sleeps: [SleepRecord]
  var detail: BatterySettings.Detail
  @Binding var range: ChargeRange
  var now: Date

  var body: some View {
    Card(padding: 0) {
      VStack(alignment: .leading, spacing: 0) {
        header
          .padding([.horizontal, .top], Metrics.l)
        chart
          .frame(height: 148)
          .padding(.horizontal, Metrics.l)
          .padding(.top, Metrics.m)
        legend
          .padding(.horizontal, Metrics.l)
          .padding(.top, Metrics.s)
          .padding(.bottom, Metrics.m)
        Divider()
        limitRow
          .padding(.horizontal, Metrics.l)
          .padding(.vertical, Metrics.m)
      }
    }
  }

  // MARK: Header

  private var header: some View {
    let reading = status?.reading
    return HStack(alignment: .top, spacing: Metrics.m) {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
          Text(reading?.percent.map { "\($0)%" } ?? "—")
            .font(.liveFigure(34))
            .foregroundStyle(reading == nil ? .tertiary : .primary)
            .contentTransition(.numericText())
          if let reading { BatteryGlyph(reading: reading) }
        }
        Text(status?.sentence ?? "Measuring…")
          .font(.title3)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .contentTransition(.opacity)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: Metrics.m)
      Picker("Show", selection: $range) {
        ForEach(ChargeRange.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel("Chart range")
    }
  }

  // MARK: Chart

  @ViewBuilder private var chart: some View {
    var samples = history.samples(since: now.addingTimeInterval(-range.seconds))
    if let reading = status?.reading, let percent = reading.percent, (samples.last?.date ?? .distantPast) < now.addingTimeInterval(-60) {
      // The latest reading, so the line always reaches the right edge.
      let _ = samples.append(.init(date: now, percent: percent, state: reading.state, batteryWatts: nil, systemWatts: nil, temperature: nil))
    }
    if samples.count < 2 {
      ZStack {
        RoundedRectangle(cornerRadius: Metrics.innerRadius)
          .fill(Palette.track.opacity(0.5))
        Text("Fills in while \(Brand.name) is open")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    } else {
      ChargeChart(samples: samples, sleeps: sleeps, range: range, now: now)
    }
  }

  private var legend: some View {
    let start = now.addingTimeInterval(-range.seconds)
    let charged = history.samples(since: start).contains(where: \.isPluggedIn) || status?.reading.isPluggedIn == true
    let slept = sleeps.contains { $0.end > start }
    return HStack(spacing: Metrics.l) {
      if charged { key("On the charger", Palette.glade.opacity(0.35)) }
      if slept { key("Asleep", ChargeChart.sleepColor.opacity(0.4)) }
      Spacer(minLength: 0)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .frame(minHeight: 14)
  }

  private func key(_ title: String, _ color: Color) -> some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
        .accessibilityHidden(true)
      Text(title)
    }
  }

  // MARK: Charge limit

  private var limitRow: some View {
    let limit = status?.limit
    return HStack(spacing: Metrics.m) {
      Label("Charge limit", systemImage: "battery.100percent.bolt")
        .labelStyle(.titleAndIcon)
      Spacer(minLength: Metrics.s)
      Text(limitText(limit))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .help(detail == .technical ? (limit?.raw ?? "") : "")
      Button("Change…") { model.openChargeLimitSettings() }
        .secondaryAction()
        .controlSize(.small)
        .help("Opens System Settings › Battery › Battery Health")
        .accessibilityLabel("Change the charge limit in System Settings")
    }
  }

  private func limitText(_ limit: ChargeLimit?) -> String {
    guard let limit else { return "—" }
    switch limit.isOn {
    case true?: return limit.percent.map { "Stops at \($0)%" } ?? "On"
    case false?: return "Off, charges to 100%"
    case nil: return "Unknown"
    }
  }
}

/// A battery symbol that fills with the charge and shows a bolt while charging.
private struct BatteryGlyph: View {
  var reading: BatteryReading

  var body: some View {
    let percent = reading.percent ?? 0
    let name: String =
      if reading.state == .charging { "battery.100percent.bolt" } else {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
      }
    Image(systemName: name)
      .font(.system(size: 22, weight: .regular))
      .symbolRenderingMode(.hierarchical)
      .foregroundStyle(percent <= 10 && reading.state == .onBattery ? Palette.critical : .secondary)
      .accessibilityHidden(true)
  }
}
