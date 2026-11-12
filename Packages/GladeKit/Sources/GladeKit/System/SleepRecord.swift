import Foundation

/// One time the Mac slept, from going to sleep to waking for the person: how long, the
/// charge either side, and every time it woke by itself in between.
public struct SleepRecord: Codable, Sendable, Identifiable, Hashable {
  /// A wake the person didn’t ask for: a "dark wake" for Power Nap, the network or a timer.
  public struct Wake: Codable, Sendable, Hashable {
    public var date: Date
    /// What woke it, in a few words: "the network", "a scheduled check-in by macOS".
    public var reason: String
    /// The log’s own wording, for the technical view.
    public var raw: String
    public var seconds: Double?
  }

  /// How many of the wakes had the same cause.
  public struct WakeCount: Codable, Sendable, Hashable {
    public var reason: String
    public var count: Int
  }

  public var start: Date
  public var end: Date
  /// Why it went to sleep, in a few words: "Lid closed", "Left idle".
  public var reason: String
  public var rawReason: String
  public var chargeBefore: Int?
  public var chargeAfter: Int?
  /// It went to sleep on battery.
  public var onBattery: Bool
  /// How it woke for the person, in a few words: "the lid was opened". `nil` when the
  /// Mac restarted instead.
  public var wokeBy: String?
  public var rawWokeBy: String?
  public var wakes: [Wake]

  public var id: Date { start }
  public var seconds: Double { max(0, end.timeIntervalSince(start)) }

  /// Percentage points lost while asleep. Negative means it charged.
  public var drain: Int? {
    guard let chargeBefore, let chargeAfter else { return nil }
    return chargeBefore - chargeAfter
  }

  /// Percentage points lost per hour asleep.
  public var drainPerHour: Double? {
    guard let drain, seconds >= 600 else { return nil }
    return Double(drain) / (seconds / 3600)
  }

  /// The causes of the wakes, most common first.
  public var wakeCounts: [WakeCount] {
    var counts: [String: Int] = [:]
    for wake in wakes { counts[wake.reason, default: 0] += 1 }
    return counts.map { WakeCount(reason: $0.key, count: $0.value) }.sorted { ($0.count, $1.reason) > ($1.count, $0.reason) }
  }

  /// "Woke 12 times by itself, mostly for the network."
  public var wakeSummary: String {
    guard let top = wakeCounts.first else { return "Didn’t wake by itself." }
    let times = wakes.count == 1 ? "once" : "\(wakes.count) times"
    if wakeCounts.count == 1 { return "Woke \(times) by itself, for \(top.reason)." }
    return "Woke \(times) by itself, mostly for \(top.reason)."
  }
}
