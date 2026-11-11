import GladeKit
import SwiftUI

/// The toolbar's scan action, always the first action on the trailing side. While a
/// scan runs it's a small spinner in the same place.
struct ScanButton: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    if model.isScanning {
      ProgressView()
        .controlSize(.small)
        .help("Scanning…")
        .accessibilityLabel("Scanning")
    } else {
      Button("Scan", systemImage: Symbols.scan) { model.startScan() }
        .help("Scan again")
    }
  }
}
