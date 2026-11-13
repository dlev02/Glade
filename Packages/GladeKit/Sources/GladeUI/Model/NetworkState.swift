import Foundation
import GladeKit

/// What the Network section shows, kept fresh by `AppModel` while it’s on screen.
public struct NetworkState {
  /// The last full reading: path, Wi-Fi, router and the speed test.
  public var status: NetworkStatus?
  /// One sample a second for the last two minutes, while the section shows.
  public var live: [NetworkWatch.Sample] = []
  /// Every app’s traffic, bytes a second, busiest first.
  public var traffic: [AppTraffic] = []
  public var wifi: WiFiLink?
  public var targets: NetworkTargets?
  /// Verdicts worked out from the live readings rather than a short burst.
  public var verdicts: [NetworkVerdict] = []
  public var history = NetworkHistory()
  public var tests: [SpeedTestResult] = []
  public var testing = false
  public var testStarted: Date?
  public var testProblem: String?
  public var loadingRouter = false
  /// The Little Snitch rules last imported, if any.
  public var littleSnitch: LittleSnitchRules?
  /// The Wi-Fi signal over the last few minutes, 0 (−90 dBm) to 100 (−30 dBm).
  var signal: [HistoryChart.Point] = []

  /// How many samples the live chart keeps.
  static let liveLength = 120

  public init() {}

  public var lastTest: SpeedTestResult? { tests.first }

  /// Latency over the last minute for one segment.
  public func stats(_ kind: NetworkTargets.Kind, seconds: Int = 60) -> LatencyStats? {
    let values = live.suffix(seconds).map { $0.value(kind) }
    guard values.contains(where: { $0 != nil }) else { return status?.latency(kind) }
    return LatencyStats(values)
  }
}
