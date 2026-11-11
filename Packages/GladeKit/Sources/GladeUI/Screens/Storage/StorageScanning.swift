import GladeKit
import SwiftUI

/// Fills the storage screen while a scan runs, with a way to stop it.
struct StorageScanning: View {
  @Environment(AppModel.self) private var model
  var done: Int
  var total: Int

  var body: some View {
    EmptyState("Looking for what can be freed", symbol: Symbols.scan) {
      VStack(spacing: Metrics.l) {
        VStack(spacing: Metrics.s) {
          ProgressView(value: Double(min(done, total)), total: Double(max(total, 1)))
            .frame(width: 240)
            .accessibilityLabel("Scan progress")
            .accessibilityValue("\(done) of \(total)")
          // What was just looked at, and the running total, from the scan’s own progress.
          if let activity = model.scanActivity {
            VStack(spacing: 2) {
              Text("\(Format.bytes(activity.found)) found so far")
                .monospacedDigit()
                .contentTransition(.numericText())
              Text("\(activity.title) checked")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .font(.callout)
            .animation(.snappy(duration: 0.18), value: activity.found)
          }
        }
        Button("Stop") { model.cancelScan() }
          .secondaryAction()
          .controlSize(.large)
          .accessibilityIdentifier("storage.stopScan")
      }
    }
  }
}

