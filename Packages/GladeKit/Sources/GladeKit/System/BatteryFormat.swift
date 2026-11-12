import Foundation

/// Wording for battery times and figures.
public enum BatteryFormat {
  /// "48 min", "1 hr 20 min".
  public static func minutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(max(minutes, 1)) min" }
    let hours = minutes / 60, rest = minutes % 60
    return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
  }

  /// "about 5 hours", "about 2½ hours", "about 40 minutes": a battery estimate, kept rough.
  public static func timeLeft(_ minutes: Int) -> String {
    if minutes < 60 { return "about \(max(5, Int((Double(minutes) / 5).rounded()) * 5)) minutes" }
    let halves = Int((Double(minutes) / 30).rounded())
    let whole = halves / 2
    let half = halves % 2 == 1
    if whole == 1 && !half { return "about an hour" }
    return "about \(whole)\(half ? "½" : "") hours"
  }

  /// "3 hours", "2 days": how long something has lasted.
  public static func duration(_ seconds: Double) -> String { Durations.phrase(seconds) }

  /// "12.4 W", "0.8 W", "45 mW".
  public static func watts(_ value: Double) -> String {
    let magnitude = abs(value)
    if magnitude < 0.1 { return "\(Int((magnitude * 1000).rounded())) mW" }
    if magnitude < 10 { return magnitude.formatted(.number.precision(.fractionLength(1))) + " W" }
    return "\(Int(magnitude.rounded())) W"
  }

  /// "34 °C".
  public static func temperature(_ celsius: Double) -> String { "\(Int(celsius.rounded())) °C" }

  /// "1.2 Wh", "340 J": energy over a period.
  public static func energy(_ joules: Double) -> String {
    let hours = joules / 3600
    if hours >= 0.1 { return hours.formatted(.number.precision(.fractionLength(hours >= 10 ? 0 : 1))) + " Wh" }
    return "\(Int((hours * 1000).rounded())) mWh"
  }
}
