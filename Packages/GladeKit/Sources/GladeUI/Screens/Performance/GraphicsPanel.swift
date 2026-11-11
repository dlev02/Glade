import GladeKit
import SwiftUI

/// How busy the graphics chip is, which chip it is, and the memory it’s using.
struct GraphicsPanel: View {
  var gpu: GPUStats?
  /// A reading has arrived, even if the GPU didn’t publish one.
  var measured: Bool
  var history: [SystemSnapshot]

  var body: some View {
    let percent = gpu?.utilizationPercent
    LivePanel(
      title: "Graphics", symbol: "cube.transparent",
      figure: percent.map(PerformanceFormat.percent) ?? "—",
      unit: nil,
      status: percent.map(PanelStatus.load) ?? (measured ? PanelStatus(text: "No reading", symbol: nil, color: .secondary, prominent: false) : .measuring),
      history: history.map { HistoryChart.Point(date: $0.date, value: min(100, max(0, $0.gpu?.utilizationPercent ?? 0))) },
      color: percent.map { Palette.load($0 / 100) } ?? .secondary,
      summary: percent.map { "\(PerformanceFormat.percent($0)) busy" } ?? "No reading"
    ) {
      PanelFact("Chip", gpu?.name ?? "—")
      PanelFact("Cores", gpu?.coreCount.map { "\($0)" } ?? "—")
      PanelFact("Memory in use", gpu?.inUseMemoryBytes.map(Format.bytes) ?? "—")
    }
  }
}
