import GladeKit
import SwiftUI

/// Memory, Processor and Graphics side by side, all the same height, dropping to two
/// columns when the window is narrow.
struct LivePanels: View {
  var readings: PerformanceReadings
  var columns: Int

  var body: some View {
    if columns >= 3 {
      HStack(alignment: .top, spacing: Metrics.l) {
        memory
        processor
        graphics
      }
      .fixedSize(horizontal: false, vertical: true)
    } else {
      VStack(spacing: Metrics.l) {
        HStack(alignment: .top, spacing: Metrics.l) {
          memory
          processor
        }
        .fixedSize(horizontal: false, vertical: true)
        graphics
      }
    }
  }

  private var memory: some View {
    MemoryPanel(memory: readings.snapshot?.memory, history: readings.history)
  }

  private var processor: some View {
    ProcessorPanel(cpu: readings.snapshot?.cpu, history: readings.history)
  }

  private var graphics: some View {
    GraphicsPanel(gpu: readings.snapshot?.gpu, measured: readings.snapshot != nil, history: readings.history)
  }
}
