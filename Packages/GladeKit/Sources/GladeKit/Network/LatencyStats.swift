import Foundation

/// How long replies took from one place, summarised: the typical time, the slow tail,
/// the worst spike, how much it wobbles and how many replies never came.
public struct LatencyStats: Codable, Sendable, Equatable {
  public var sent: Int
  public var received: Int
  /// Typical round trip in milliseconds (the median).
  public var typical: Double?
  /// The slowest 5% start here.
  public var slow: Double?
  public var worst: Double?
  public var best: Double?
  /// How much one reply differs from the next on average, in milliseconds. High
  /// jitter is what makes calls stutter and game streams hitch.
  public var jitter: Double?

  public var lossPercent: Double { sent == 0 ? 0 : Double(sent - received) / Double(sent) * 100 }
  public var reachable: Bool { received > 0 }

  /// - Parameter replies: Round trips in milliseconds, in order, `nil` for a lost one.
  public init(_ replies: [Double?]) {
    sent = replies.count
    let times = replies.compactMap { $0 }
    received = times.count
    let sorted = times.sorted()
    typical = Self.percentile(sorted, 0.5)
    slow = Self.percentile(sorted, 0.95)
    worst = sorted.last
    best = sorted.first
    if times.count >= 2 {
      let steps = zip(times, times.dropFirst()).map { abs($1 - $0) }
      jitter = steps.reduce(0, +) / Double(steps.count)
    }
  }

  static func percentile(_ sorted: [Double], _ fraction: Double) -> Double? {
    guard !sorted.isEmpty else { return nil }
    let index = Int((Double(sorted.count - 1) * fraction).rounded())
    return sorted[min(sorted.count - 1, max(0, index))]
  }

  /// “4 ms, spikes to 31 ms” or “no replies”.
  public var sentence: String {
    guard let typical else { return "no replies" }
    var text = "\(Self.ms(typical))"
    if let worst, worst > max(typical * 3, typical + 20) { text += ", spikes to \(Self.ms(worst))" }
    if lossPercent >= 1 { text += ", \(Int(lossPercent.rounded()))% lost" }
    return text
  }

  public static func ms(_ value: Double) -> String {
    value < 10 ? String(format: "%.1f ms", value) : "\(Int(value.rounded())) ms"
  }
}
