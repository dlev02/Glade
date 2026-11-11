import GladeKit
import SwiftUI

/// Shown beside the list when no clean is selected: everything Glade has removed.
struct HistorySummary: View {
  var cleans: [Receipt]

  var body: some View {
    let total = cleans.reduce(Int64(0)) { $0 + $1.removedBytes }
    VStack(spacing: Metrics.xs) {
      Text(Format.bytes(total))
        .font(.figure(40))
      Text(cleans.count == 1 ? "removed in 1 clean" : "removed in \(cleans.count) cleans")
        .font(.title3)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }
}
