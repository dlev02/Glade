import GladeKit
import SwiftUI

/// Latency to the internet now, its last two minutes, and each segment beneath, the
/// way Discord shows a call’s ping: the figure, the line, and spikes standing out.
struct LatencyPanel: View {
  var live: [NetworkWatch.Sample]
  var stats: [NetworkTargets.Kind: LatencyStats]

  var body: some View {
    let internet = stats[.internet]
    let latest = live.last?.internet ?? internet?.typical
    LivePanel(
      title: "Latency", symbol: "point.3.connected.trianglepath.dotted",
      figure: latest.map { LatencyStats.ms($0) } ?? "—", unit: "to the internet",
      status: NetworkFormat.steadiness(internet, kind: .internet),
      history: history, color: NetworkFormat.health(.internet, internet).color == .secondary ? Palette.good : NetworkFormat.health(.internet, internet).color,
      summary: NetworkTargets.Kind.allCases.map { "\($0.title) \(stats[$0]?.sentence ?? "not measured")" }.joined(separator: ", ")
    ) {
      ForEach(NetworkTargets.Kind.allCases, id: \.self) { kind in
        PanelFact(kind.title, value(stats[kind]), dot: NetworkFormat.health(kind, stats[kind]).color)
      }
      PanelFact("Jitter", NetworkFormat.ms(internet?.jitter))
    }
  }

  /// “4.1 ms” or “4.1 ms · 38 max” when it spiked.
  private func value(_ stats: LatencyStats?) -> String {
    guard let stats, stats.sent > 0 else { return "—" }
    guard stats.reachable else { return "No replies" }
    var text = NetworkFormat.ms(stats.typical)
    if let worst = stats.worst, let typical = stats.typical, worst > max(typical * 3, typical + 20) { text += " · \(Int(worst)) max" }
    if stats.lossPercent >= 1 { text += " · \(Int(stats.lossPercent.rounded()))% lost" }
    return text
  }

  /// The internet’s latency on a scale that fits the worst of it, lost replies at the top.
  private var history: [HistoryChart.Point] {
    let values = live.compactMap(\.internet)
    let ceiling = max(40, (values.max() ?? 0) * 1.15)
    return live.map { HistoryChart.Point(date: $0.date, value: $0.internet.map { min(100, $0 / ceiling * 100) } ?? 100) }
  }
}
