import SwiftUI

/// Fills the storage screen while a scan runs, with a way to stop it.
struct StorageScanning: View {
  @Environment(AppModel.self) private var model
  var done: Int
  var total: Int

  var body: some View {
    EmptyState("Looking for what can be freed", symbol: Symbols.scan) {
      VStack(spacing: Metrics.l) {
        ProgressView(value: Double(min(done, total)), total: Double(max(total, 1)))
          .frame(width: 240)
          .accessibilityLabel("Scan progress")
          .accessibilityValue("\(done) of \(total)")
        Button("Stop", role: .cancel) { model.cancelScan() }
          .secondaryAction()
      }
    }
  }
}
