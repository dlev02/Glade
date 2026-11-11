import GladeKit
import SwiftUI

/// The storage screen before anything has been scanned.
struct StorageEmptyState: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      if !model.hasFullDiskAccess {
        StorageAccessBanner()
          .padding(.horizontal, Metrics.l)
          .padding(.top, Metrics.m)
      }
      EmptyState("Nothing scanned yet", symbol: AppModel.Section.storage.symbol) {
        Button("Scan", systemImage: "magnifyingglass") { model.startScan() }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .disabled(model.isScanning)
      }
    }
  }
}
