import GladeKit
import SwiftUI

/// How busy the processor is, split between apps and macOS, and how hard each core
/// is working.
struct ProcessorPanel: View {
  var cpu: CPUStats?
  var history: [SystemSnapshot]

  var body: some View {
    LivePanel(
      title: "Processor", symbol: "cpu",
      figure: cpu.map { PerformanceFormat.percent($0.totalPercent) } ?? "—",
      unit: nil,
      status: cpu.map { PanelStatus.load($0.totalPercent) } ?? .measuring,
      history: history.map { HistoryChart.Point(date: $0.date, value: min(100, max(0, $0.cpu.totalPercent))) },
      color: cpu.map { Palette.load($0.totalPercent / 100) } ?? .secondary,
      summary: cpu.map { "\(PerformanceFormat.percent($0.totalPercent)) busy, \(PerformanceFormat.load($0.totalPercent).lowercased())" } ?? "Measuring"
    ) {
      CoreStrip(cores: cpu?.perCorePercent ?? [])
      PanelFact("Apps", cpu.map { PerformanceFormat.percent($0.userPercent) } ?? "—")
      PanelFact("macOS", cpu.map { PerformanceFormat.percent($0.systemPercent) } ?? "—")
      if let performance = cpu?.performanceCores, let efficiency = cpu?.efficiencyCores, performance + efficiency > 0 {
        PanelFact("Performance cores", "\(performance)")
        PanelFact("Efficiency cores", "\(efficiency)")
      } else {
        PanelFact("Cores", cpu.map { "\($0.logicalCores)" } ?? "—")
      }
    }
  }
}

/// One tiny bar per core, drawn in a single pass.
private struct CoreStrip: View {
  var cores: [Double]

  var body: some View {
    Canvas { context, size in
      guard !cores.isEmpty else { return }
      let gap: CGFloat = 2
      let width = max(1, (size.width - gap * CGFloat(cores.count - 1)) / CGFloat(cores.count))
      for (index, value) in cores.enumerated() {
        let x = CGFloat(index) * (width + gap)
        let track = Path(roundedRect: CGRect(x: x, y: 0, width: width, height: size.height), cornerRadius: 1.5)
        context.fill(track, with: .color(.primary.opacity(0.08)))
        let fraction = min(max(value / 100, 0), 1)
        let height = max(1.5, size.height * fraction)
        let bar = Path(roundedRect: CGRect(x: x, y: size.height - height, width: width, height: height), cornerRadius: 1.5)
        context.fill(bar, with: .color(Palette.load(fraction)))
      }
    }
    .frame(height: 14)
    .accessibilityHidden(true)
  }
}
