import GladeKit
import SwiftUI

/// The storage screen before anything has been scanned.
struct StorageEmptyState: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    EmptyState("Nothing scanned yet", symbol: AppModel.Section.storage.symbol) {
      Button("Scan Storage") { model.startScan() }
        .principalAction()
        .controlSize(.large)
        .disabled(model.isScanning)
        .accessibilityIdentifier("storage.scanStorage")
    }
  }
}
