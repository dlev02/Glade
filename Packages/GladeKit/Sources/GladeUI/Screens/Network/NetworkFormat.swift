import GladeKit
import SwiftUI

/// How network readings look: one set of thresholds, so a segment’s colour, its word
/// and the verdict never disagree.
enum NetworkFormat {
  enum Health {
    case good, slow, bad, unknown

    var color: Color {
      switch self {
      case .good: Palette.good
      case .slow: Palette.warning
      case .bad: Palette.critical
      case .unknown: .secondary
      }
    }
  }

  /// Slower than these (the slowest 5%), each segment is slow; past double, bad.
  static func limit(_ kind: NetworkTargets.Kind) -> Double {
    switch kind {
    case .router: 20
    case .provider: 40
    case .internet: 80
    }
  }

  static func health(_ kind: NetworkTargets.Kind, _ stats: LatencyStats?) -> Health {
    guard let stats else { return .unknown }
    guard stats.reachable else { return .bad }
    let slow = stats.slow ?? stats.typical ?? 0
    if stats.lossPercent >= 5 || slow > limit(kind) * 2 { return .bad }
    if stats.lossPercent >= 1 || slow > limit(kind) { return .slow }
    return .good
  }

  /// “Steady”, “Some spikes”, “Dropping replies”.
  static func steadiness(_ stats: LatencyStats?, kind: NetworkTargets.Kind) -> PanelStatus {
    guard let stats, stats.sent > 0 else { return .measuring }
    switch health(kind, stats) {
    case .good: return PanelStatus(text: "Steady", symbol: nil, color: Palette.good, prominent: false)
    case .slow: return PanelStatus(text: stats.lossPercent >= 1 ? "Some lost" : "Some spikes", symbol: nil, color: Palette.warning, prominent: true)
    case .bad: return PanelStatus(text: stats.reachable ? "Unsteady" : "No replies", symbol: nil, color: Palette.critical, prominent: true)
    case .unknown: return .measuring
    }
  }

  static func ms(_ value: Double?) -> String {
    value.map { LatencyStats.ms($0) } ?? "—"
  }

  /// “1.2 MB/s”, or “—” below a kilobyte a second.
  static func rate(_ bytesPerSecond: Double) -> String {
    bytesPerSecond < 1_000 ? "—" : NetworkDiagnosis.rate(bytesPerSecond)
  }

  static func mbps(_ value: Double) -> String {
    value >= 100 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
  }

  static func color(_ severity: NetworkVerdict.Severity) -> Color {
    switch severity {
    case .good: Palette.good
    case .notice: Palette.warning
    case .problem: Palette.critical
    }
  }

  static func symbol(_ severity: NetworkVerdict.Severity) -> String {
    switch severity {
    case .good: "checkmark.circle.fill"
    case .notice: "exclamationmark.circle.fill"
    case .problem: "xmark.octagon.fill"
    }
  }
}
