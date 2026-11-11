import Foundation
import GladeKit

/// Wording for the figures on the Performance screen.
enum PerformanceFormat {
  /// "42%", or "4.2%" / "0.3%" below ten so small shares still tell apart.
  static func percent(_ value: Double) -> String {
    let clamped = max(value, 0)
    if clamped < 0.05 { return "0%" }
    if clamped < 10 { return clamped.formatted(.number.precision(.fractionLength(1))) + "%" }
    return "\(Int(clamped.rounded()))%"
  }

  /// "now" for the front app, "4 min ago" within the hour, "3 hr ago" within the day,
  /// then the coarser wording used elsewhere.
  static func lastUsed(_ app: AppUsage, now: Date = Date()) -> String {
    if app.isFrontmost { return "now" }
    guard let date = app.lastActive else { return "—" }
    let seconds = now.timeIntervalSince(date)
    switch seconds {
    case ..<60: return "just now"
    case ..<3_600: return "\(Int(seconds / 60)) min ago"
    case ..<86_400: return "\(Int(seconds / 3_600)) hr ago"
    default: return Format.age(date, now: now)
    }
  }

  /// "3 days, 4 hours".
  static func uptime(_ seconds: Double) -> String {
    Duration.seconds(max(seconds, 60)).formatted(
      .units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 2)
    )
  }

  /// How busy something is, in a word or two.
  static func load(_ percent: Double) -> String {
    switch percent {
    case ..<25: "Light"
    case ..<70: "Moderate"
    case ..<90: "Busy"
    default: "Maxed out"
    }
  }
}
