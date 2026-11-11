import GladeKit
import SwiftUI

/// One quiet line at the foot of the screen: heat when it matters, power, Low Power
/// Mode, and how long the Mac has been up.
struct StatusFooter: View {
  var snapshot: SystemSnapshot?

  var body: some View {
    HStack(spacing: Metrics.l) {
      if let snapshot {
        if snapshot.thermal != .nominal {
          item(thermalText(snapshot.thermal), "thermometer.medium", color: snapshot.thermal == .fair ? nil : Palette.warning)
        }
        if let power = powerText(snapshot.power) {
          item(power, snapshot.power.onBattery ? "battery.75percent" : "powerplug.fill")
        }
        if snapshot.power.lowPowerMode {
          item("Low Power Mode", "leaf.fill")
        }
        item("Up \(PerformanceFormat.uptime(snapshot.uptimeSeconds))", "clock")
      } else {
        // Holds the line's height so nothing shifts when the first reading lands.
        Text(" ")
      }
      Spacer(minLength: 0)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
  }

  private func item(_ text: String, _ symbol: String, color: Color? = nil) -> some View {
    Label {
      Text(text).monospacedDigit()
    } icon: {
      Image(systemName: symbol)
        .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary))
    }
  }

  private func thermalText(_ state: ThermalState) -> String {
    switch state {
    case .nominal: "Cool"
    case .fair: "Warm"
    case .serious: "Hot: macOS is slowing the processor"
    case .critical: "Very hot: macOS is slowing the processor hard"
    }
  }

  private func powerText(_ power: PowerStats) -> String? {
    guard power.hasBattery else { return nil }
    let charge = power.batteryPercent.map { " · \($0)%" } ?? ""
    if power.onBattery { return "On battery\(charge)" }
    return (power.isCharging == true ? "Charging" : "Plugged in") + charge
  }
}
