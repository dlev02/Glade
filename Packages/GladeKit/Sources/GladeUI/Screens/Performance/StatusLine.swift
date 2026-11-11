import GladeKit

/// One quiet line under the Performance title: heat when it matters, power, Low Power
/// Mode, and how long the Mac has been up. "Warm · Plugged in · Up 2 days".
enum StatusLine {
  static func text(_ snapshot: SystemSnapshot?) -> String {
    guard let snapshot else { return "" }
    var parts: [String] = []
    if snapshot.thermal != .nominal { parts.append(thermalText(snapshot.thermal)) }
    if let power = powerText(snapshot.power) { parts.append(power) }
    if snapshot.power.lowPowerMode { parts.append("Low Power Mode") }
    parts.append("Up \(PerformanceFormat.uptime(snapshot.uptimeSeconds))")
    return parts.joined(separator: " · ")
  }

  private static func thermalText(_ state: ThermalState) -> String {
    switch state {
    case .nominal: "Cool"
    case .fair: "Warm"
    case .serious: "Hot: macOS is slowing the processor"
    case .critical: "Very hot: macOS is slowing the processor hard"
    }
  }

  private static func powerText(_ power: PowerStats) -> String? {
    guard power.hasBattery else { return nil }
    let charge = power.batteryPercent.map { " · \($0)%" } ?? ""
    if power.onBattery { return "On battery\(charge)" }
    return (power.isCharging == true ? "Charging" : "Plugged in") + charge
  }
}
