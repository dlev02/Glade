import GladeKit
import SwiftUI

/// Memory in use, how hard macOS is working to find more, and what the used memory
/// is made of.
struct MemoryPanel: View {
  var memory: MemoryStats?
  var history: [SystemSnapshot]

  var body: some View {
    LivePanel(
      title: "Memory", symbol: "memorychip",
      figure: memory.map { Format.bytes($0.usedBytes) } ?? "—",
      unit: memory.map { "of \(Format.bytes($0.totalBytes))" },
      status: memory.map { PanelStatus.pressure($0.pressure) } ?? .measuring,
      history: history.map {
        HistoryChart.Point(date: $0.date, value: min(100, Double($0.memory.usedBytes) / Double(max($0.memory.totalBytes, 1)) * 100))
      },
      color: color,
      summary: memory.map { "\(Format.bytes($0.usedBytes)) used of \(Format.bytes($0.totalBytes)), pressure \($0.pressure.title.lowercased())" } ?? "Measuring"
    ) {
      MemoryBar(parts: parts, total: memory?.totalBytes ?? 1)
      ForEach(parts) { fact($0) }
      PanelFact("Swap", memory.map { Format.bytes($0.swapUsedBytes) } ?? "—")
    }
  }

  private func fact(_ part: MemoryPart) -> some View {
    PanelFact(part.title, memory == nil ? "—" : Format.bytes(part.bytes), dot: part.color)
  }

  private var parts: [MemoryPart] {
    [
      MemoryPart(id: "app", title: "App", bytes: memory?.appBytes ?? 0, color: .blue),
      MemoryPart(id: "wired", title: "Wired", bytes: memory?.wiredBytes ?? 0, color: .orange),
      MemoryPart(id: "compressed", title: "Compressed", bytes: memory?.compressedBytes ?? 0, color: .purple),
      MemoryPart(id: "cached", title: "Cached files", bytes: memory?.cachedFilesBytes ?? 0, color: .teal),
    ]
  }

  private var color: Color {
    guard let memory else { return .secondary }
    switch memory.pressure {
    case .normal: return Palette.load(Double(memory.usedBytes) / Double(max(memory.totalBytes, 1)) * 0.85)
    case .warning: return Palette.warning
    case .critical: return Palette.critical
    }
  }
}

/// One kind of memory in the stacked bar.
private struct MemoryPart: Identifiable {
  var id: String
  var title: String
  var bytes: Int64
  var color: Color
}

/// The whole of memory as one thin bar: each kind in use, then what's free.
private struct MemoryBar: View {
  var parts: [MemoryPart]
  var total: Int64

  var body: some View {
    Canvas { context, size in
      var x: CGFloat = 0
      let gap: CGFloat = 1.5
      for part in parts where part.bytes > 0 {
        let width = max(2, size.width * CGFloat(part.bytes) / CGFloat(max(total, 1)))
        let rect = CGRect(x: x, y: 0, width: min(width, size.width - x), height: size.height)
        guard rect.width > 0 else { break }
        context.fill(Path(rect), with: .color(part.color))
        x += width + gap
      }
    }
    .frame(height: 6)
    .background(Palette.track)
    .clipShape(.capsule)
    .accessibilityHidden(true)
  }
}
