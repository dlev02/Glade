import SwiftUI

/// Fills the storage screen while a scan runs, with a way to stop it.
struct StorageScanning: View {
  @Environment(AppModel.self) private var model
  var done: Int
  var total: Int

  var body: some View {
    VStack(spacing: Metrics.l) {
      Text("Looking for what can be freed…")
        .font(.title3)
        .foregroundStyle(.secondary)
      ProgressView(value: Double(min(done, total)), total: Double(max(total, 1)))
        .frame(width: 280)
        .accessibilityLabel("Scan progress")
      Button("Stop", role: .cancel) { model.cancelScan() }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
