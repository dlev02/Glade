import GladeKit
import SwiftUI

/// The toolbar’s scan action, always the first action on the trailing side. While a
/// scan runs it keeps the same round button, its symbol turning, and a click stops
/// the scan.
struct ScanButton: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let scanning = model.isScanning
    Button(scanning ? "Stop Scanning" : "Scan", systemImage: Symbols.scan) {
      if scanning { model.cancelScan() } else { model.startScan() }
    }
    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: scanning && !reduceMotion)
    .help(scanning ? "Scanning… Click to stop (⌘.)" : "Scan again (⌘R)")
    .accessibilityValue(scanning ? "Scanning" : "")
    .accessibilityIdentifier("toolbar.scan")
  }
}
