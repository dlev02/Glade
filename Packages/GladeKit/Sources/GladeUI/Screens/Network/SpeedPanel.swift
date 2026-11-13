import GladeKit
import SwiftUI

/// The last speed test: download large, its history, and what it means for calls,
/// streaming and games beneath. A test only runs from the toolbar’s Test Speed.
struct SpeedPanel: View {
  var tests: [SpeedTestResult]
  var testing: Bool
  var problem: String?

  var body: some View {
    let last = tests.first
    LivePanel(
      title: "Speed", symbol: "speedometer",
      figure: last.map { NetworkFormat.mbps($0.downloadMbps) } ?? "—", unit: last == nil ? nil : "Mbps down",
      status: status(last),
      history: history, color: Palette.good,
      summary: last.map { "\(Int($0.downloadMbps)) megabits down, \(Int($0.uploadMbps)) up, tested \(Format.age($0.date))" } ?? "Not tested"
    ) {
      if let last {
        PanelFact("Upload", "\(NetworkFormat.mbps(last.uploadMbps)) Mbps")
        PanelFact("When busy", busy(last))
        ForEach(last.activities.prefix(3), id: \.name) { activity in
          PanelFact(activity.name, activity.sentence, dot: color(activity.rating))
        }
      } else if let problem {
        Text(problem)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        PanelFact("Download", "—")
        PanelFact("Upload", "—")
        PanelFact("When busy", "—")
      }
    }
  }

  private func status(_ last: SpeedTestResult?) -> PanelStatus {
    if testing { return PanelStatus(text: "Testing…", symbol: nil, color: .secondary, prominent: false) }
    if problem != nil { return PanelStatus(text: "Failed", symbol: nil, color: Palette.critical, prominent: true) }
    guard let last else { return PanelStatus(text: "Not tested", symbol: nil, color: .secondary, prominent: false) }
    let age = Date().timeIntervalSince(last.date) < 60 ? "Just now" : last.date.formatted(.relative(presentation: .named)).capitalizedFirst
    return PanelStatus(text: age, symbol: nil, color: .secondary, prominent: false)
  }

  /// “+12 ms” when it barely slows, more words when it slows a lot.
  private func busy(_ test: SpeedTestResult) -> String {
    guard let added = test.addedWhenBusy else { return "—" }
    return added <= 30 ? "Barely slower" : "+\(Int(added)) ms slower"
  }

  private func color(_ rating: SpeedTestResult.Activity.Rating) -> Color {
    switch rating {
    case .good: Palette.good
    case .okay: Palette.warning
    case .poor: Palette.critical
    }
  }

  /// Download over the recent tests, oldest first, against the fastest of them.
  private var history: [HistoryChart.Point] {
    let recent = tests.prefix(12).reversed()
    let ceiling = max(1, (recent.map(\.downloadMbps).max() ?? 1) * 1.1)
    return recent.map { HistoryChart.Point(date: $0.date, value: $0.downloadMbps / ceiling * 100) }
  }
}

extension String {
  /// “2 hours ago” as “2 hours ago”, “yesterday” as “Yesterday”.
  var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
